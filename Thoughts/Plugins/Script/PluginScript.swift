import Foundation
import JavaScriptCore
import os

/// Скрипт одного плагина (`main.js`) в своём JSContext на своей очереди. Скрипту
/// доступно только то, что даёт объект `thoughts`: регистрация конвертеров, `fetch`
/// на объявленные в манифесте хосты (только https), маленькое хранилище и
/// `console.log`. Ни файлов, ни таймеров, ни доступа к карточкам.
nonisolated final class PluginScript: @unchecked Sendable {
    let pluginID: String
    let allowedHosts: Set<String>
    /// Отвечает ли скрипт дольше обычного (есть сеть) — см. ConverterService.
    var usesNetwork: Bool { !allowedHosts.isEmpty }

    private let queue: DispatchQueue
    private let log: Logger
    // Всё ниже — только на `queue`.
    private var context: JSContext?
    private var converters: [String: JSValue] = [:]
    private var loadError: String?

    private static let maxResponseSize = 1_000_000
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    init(pluginID: String, scriptURL: URL, allowedHosts: [String]) {
        self.pluginID = pluginID
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        queue = DispatchQueue(label: "plugin.\(pluginID)", qos: .userInitiated)
        log = Logger(subsystem: "com.alxeu.Thoughts.plugins", category: pluginID)
        queue.async { [self] in load(scriptURL) }
    }

    /// Зарегистрированные скриптом конвертеры и ошибка загрузки (ждёт загрузку).
    func status(_ completion: @escaping @Sendable ([String], String?) -> Void) {
        queue.async { [self] in completion(Array(converters.keys), loadError) }
    }

    /// Строка → результат конвертера `id` или nil. `completion` — на любой очереди.
    func convert(_ line: String, with id: String, completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let context, let converter = converters[id],
                  let run = context.objectForKeyedSubscript("__convert") else { return completion(nil) }
            let done: @convention(block) (JSValue, JSValue) -> Void = { value, _ in
                completion(value.isNull || value.isUndefined ? nil : value.toString())
            }
            run.call(withArguments: [converter, line, unsafeBitCast(done, to: AnyObject.self)])
        }
    }

    // MARK: - Загрузка

    private func load(_ url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else {
            loadError = "The script can\u{2019}t be read."
            return
        }
        context.name = pluginID
        context.exceptionHandler = { [log] _, exception in
            log.error("\(exception?.toString() ?? "error", privacy: .public)")
        }
        installBridge(in: context)
        context.evaluateScript(Self.bootstrap)
        context.objectForKeyedSubscript("thoughts")?.setObject(Self.localeInfo, forKeyedSubscript: "locale" as NSString)
        context.evaluateScript(source, withSourceURL: url)
        if let exception = context.exception {
            loadError = "The script failed: \(exception.toString() ?? "error")"
            context.exception = nil
        }
        self.context = context
    }

    /// `thoughts.locale` — чтобы конвертер выбирал цель по умолчанию, как Spotlight:
    /// «5ft» → см в метрической системе, «100usd» → валюта региона пользователя.
    private static var localeInfo: [String: Any] {
        let locale = Locale.current
        return [
            "identifier": locale.identifier,
            "language": locale.language.languageCode?.identifier ?? "en",
            "region": locale.region?.identifier ?? "",
            "currency": locale.currency?.identifier ?? "USD",
            "usesMetricSystem": locale.measurementSystem != .us
        ]
    }

    /// Обёртки на JS над нативными функциями: Promise для fetch, единый вызов convert.
    private static let bootstrap = """
    var thoughts = {
      converter: function (id, def) {
        if (typeof id !== "string" || !def || typeof def.convert !== "function") throw new Error("thoughts.converter(id, { convert(line) })");
        __register(id, def);
      },
      fetch: function (url, options) {
        return new Promise(function (resolve, reject) {
          __fetch(String(url), options || {}, function (status, body) {
            resolve({ status: status, ok: status >= 200 && status < 300,
                      text: function () { return body; }, json: function () { return JSON.parse(body); } });
          }, function (message) { reject(new Error(message)); });
        });
      },
      storage: {
        get: function (key) { var v = __storageGet(String(key)); return v == null ? null : JSON.parse(v); },
        set: function (key, value) { __storageSet(String(key), value === undefined ? null : JSON.stringify(value)); }
      }
    };
    var console = { log: function () { __log(Array.prototype.join.call(arguments, " ")); } };
    console.error = console.warn = console.info = console.log;
    function __convert(def, line, done) {
      try {
        Promise.resolve(def.convert(line)).then(function (v) {
          done(v === null || v === undefined || v === "" ? null : String(v), null);
        }, function (e) { done(null, String(e)); });
      } catch (e) { done(null, String(e)); }
    }
    """

    private func installBridge(in context: JSContext) {
        let register: @convention(block) (String, JSValue) -> Void = { [unowned self] id, def in
            converters[id] = def
        }
        let log: @convention(block) (String) -> Void = { [log] message in
            log.info("\(message, privacy: .public)")
        }
        let storageKey = "plugin.storage.\(pluginID)"
        let storageGet: @convention(block) (String) -> Any? = { key in
            (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String])?[key]
        }
        let storageSet: @convention(block) (String, JSValue) -> Void = { key, value in
            var all = (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String]) ?? [:]
            if value.isNull || value.isUndefined {
                all.removeValue(forKey: key)
            } else if let text = value.toString(), text.utf8.count <= 100_000, all.count < 1_000 {
                all[key] = text
            }
            UserDefaults.standard.set(all, forKey: storageKey)
        }
        let fetch: @convention(block) (String, JSValue, JSValue, JSValue) -> Void = { [unowned self] url, options, resolve, reject in
            self.fetch(url, options: options, resolve: resolve, reject: reject)
        }
        context.setObject(register, forKeyedSubscript: "__register" as NSString)
        context.setObject(log, forKeyedSubscript: "__log" as NSString)
        context.setObject(storageGet, forKeyedSubscript: "__storageGet" as NSString)
        context.setObject(storageSet, forKeyedSubscript: "__storageSet" as NSString)
        context.setObject(fetch, forKeyedSubscript: "__fetch" as NSString)
    }

    // MARK: - Сеть

    /// Только https и только хосты из `permissions.network`; ответ ≤ 1 МБ.
    private func fetch(_ string: String, options: JSValue, resolve: JSValue, reject: JSValue) {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            reject.call(withArguments: ["\(pluginID) may not connect to \(URL(string: string)?.host ?? string). Add the host to permissions.network."])
            return
        }
        var request = URLRequest(url: url)
        if let method = options.forProperty("method"), method.isString { request.httpMethod = method.toString() }
        if let body = options.forProperty("body"), body.isString { request.httpBody = body.toString().data(using: .utf8) }
        if let headers = options.forProperty("headers")?.toDictionary() as? [String: Any] {
            for (name, value) in headers { request.setValue("\(value)", forHTTPHeaderField: name) }
        }
        Self.session.dataTask(with: request) { [queue] data, response, error in
            queue.async {
                if let error {
                    reject.call(withArguments: [error.localizedDescription])
                } else if let data, data.count > Self.maxResponseSize {
                    reject.call(withArguments: ["The response is larger than 1 MB."])
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    resolve.call(withArguments: [status, String(decoding: data ?? Data(), as: UTF8.self)])
                }
            }
        }.resume()
    }
}
