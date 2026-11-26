import Foundation

// MARK: - Araçlar (web_ara, sayfa_oku, kod_calistir) ve bulut "Uzman" modu

let UZMAN = "uzman"
func modelAdi(_ m: String) -> String { m == UZMAN ? "☁︎ Uzman (gpt-oss-120b)" : m }

struct AracCagrisi {
    var id: String
    var ad: String
    var argumanlar: [String: Any]
    var hamArguman: String   // OpenAI biçimi için ham JSON metni
}

struct KodOnay: Identifiable {
    let id = UUID()
    let dil: String
    let kod: String
}

enum Araclar {
    static let tanimlar: [[String: Any]] = [
        fonk("web_ara", "İnternette güncel bilgi arar (haber, fiyat, sürüm, tarih, kişi, şirket). Bilgin eski olabilir; güncel ya da emin olmadığın her şeyde kullan.",
             ["sorgu": ["type": "string", "description": "Aranacak soru ya da anahtar kelimeler"]], ["sorgu"]),
        fonk("sayfa_oku", "Bir web sayfasını açar ve metnini döndürür.",
             ["url": ["type": "string", "description": "http veya https adresi"]], ["url"]),
        fonk("kod_calistir", "Kodu bilgisayarda geçici bir klasörde çalıştırır, çıktıyı ve hataları döndürür. Yazdığın kodu test etmek için kullan.",
             ["dil": ["type": "string", "enum": ["python", "node", "bash", "swift"], "description": "Programlama dili"],
              "kod": ["type": "string", "description": "Çalıştırılacak tam kod"]], ["dil", "kod"]),
    ]

    private static func fonk(_ ad: String, _ aciklama: String, _ ozellik: [String: Any], _ gerekli: [String]) -> [String: Any] {
        ["type": "function", "function": ["name": ad, "description": aciklama,
                                          "parameters": ["type": "object", "properties": ozellik, "required": gerekli]]]
    }

    static func durumMetni(_ c: AracCagrisi) -> String {
        switch c.ad {
        case "web_ara": return "🔎 Aranıyor: \(c.argumanlar["sorgu"] as? String ?? "")"
        case "sayfa_oku": return "📄 Okunuyor: \(c.argumanlar["url"] as? String ?? "")"
        case "kod_calistir": return "▶︎ Kod çalıştırılıyor (\(c.argumanlar["dil"] as? String ?? "?"))"
        default: return "⚙︎ \(c.ad)"
        }
    }

    // MARK: Çalıştırıcılar
    static func webAra(_ sorgu: String) async -> String {
        let yol = NSHomeDirectory() + "/Alex/bin/pro-ara"
        guard !sorgu.isEmpty, FileManager.default.isExecutableFile(atPath: yol) else { return "Arama yapılamadı (pro-ara yok)." }
        let r = await calistir(yol, [sorgu], zaman: 150)
        let t = r.cikti.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.kod == 0 && !t.isEmpty ? String(t.prefix(8000)) : "Arama başarısız oldu."
    }

    static func sayfaOku(_ adres: String) async -> String {
        guard let url = URL(string: adres), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return "Geçersiz adres."
        }
        var istek = URLRequest(url: url, timeoutInterval: 20)
        istek.setValue("Mozilla/5.0 (Macintosh) OllamaSohbet", forHTTPHeaderField: "User-Agent")
        do {
            let (v, y) = try await URLSession.shared.data(for: istek)
            if let h = y as? HTTPURLResponse, h.statusCode >= 400 { return "Sayfa açılamadı (HTTP \(h.statusCode))." }
            var s = String(data: v, encoding: .utf8) ?? String(data: v, encoding: .isoLatin1) ?? ""
            s = degis(s, "(?is)<(script|style|noscript|svg|head)\\b.*?</\\1>", " ")
            s = degis(s, "(?s)<!--.*?-->", " ")
            s = degis(s, "(?i)<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>", "\n")
            s = degis(s, "<[^>]+>", " ")
            for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
                s = s.replacingOccurrences(of: a, with: b)
            }
            s = degis(degis(s, "[ \\t]+", " "), "\\s*\\n\\s*", "\n")
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Sayfada okunabilir metin yok." : String(t.prefix(8000))
        } catch {
            return "Sayfa açılamadı: \(error.localizedDescription)"
        }
    }

    static func kodCalistir(dil: String, kod: String) async -> String {
        let fm = FileManager.default
        let klasor = fm.temporaryDirectory.appending(path: "ollamasohbet-\(UUID().uuidString)")
        try? fm.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: klasor) }
        let (dosyaAdi, yol, arg): (String, String, [String]) = {
            switch dil {
            case "node":
                let n = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first { fm.isExecutableFile(atPath: $0) } ?? "/usr/bin/env"
                return ("main.js", n, n == "/usr/bin/env" ? ["node"] : [])
            case "bash": return ("main.sh", "/bin/bash", [])
            case "swift": return ("main.swift", "/usr/bin/swift", [])
            default: return ("main.py", "/usr/bin/env", ["python3"])
            }
        }()
        let dosya = klasor.appending(path: dosyaAdi)
        do { try kod.write(to: dosya, atomically: true, encoding: .utf8) } catch { return "Dosya yazılamadı." }
        let r = await calistir(yol, arg + [dosya.path], zaman: 30, klasor: klasor)
        var cikti = r.cikti.isEmpty ? "(çıktı yok)" : r.cikti
        if cikti.count > 8000 { cikti = String(cikti.prefix(8000)) + "\n…(kısaltıldı)" }
        return r.zamanAsimi ? "ZAMAN AŞIMI (30 sn)\n\(cikti)" : "Çıkış kodu: \(r.kod)\n\(cikti)"
    }

    private static func degis(_ s: String, _ desen: String, _ yerine: String) -> String {
        guard let r = try? NSRegularExpression(pattern: desen) else { return s }
        return r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: yerine)
    }

    struct Sonuc { var kod: Int32; var cikti: String; var zamanAsimi: Bool }

    /// Süreci çalıştırır; stdout+stderr bir dosyaya yazılır (boru tıkanması olmaz).
    static func calistir(_ yol: String, _ arg: [String], zaman: Double, klasor: URL? = nil) async -> Sonuc {
        let fm = FileManager.default
        let log = fm.temporaryDirectory.appending(path: "ollamasohbet-cikti-\(UUID().uuidString).txt")
        fm.createFile(atPath: log.path, contents: nil)
        defer { try? fm.removeItem(at: log) }
        guard let fh = try? FileHandle(forWritingTo: log) else { return Sonuc(kod: -1, cikti: "Çıktı dosyası açılamadı.", zamanAsimi: false) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yol)
        p.arguments = arg
        if let klasor { p.currentDirectoryURL = klasor }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + NSHomeDirectory() + "/.local/bin"
        p.environment = env
        p.standardOutput = fh
        p.standardError = fh
        p.standardInput = FileHandle.nullDevice
        final class Bayrak: @unchecked Sendable { var asim = false }
        let bayrak = Bayrak()
        let kod: Int32 = await withCheckedContinuation { devam in
            p.terminationHandler = { devam.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch {
                p.terminationHandler = nil
                devam.resume(returning: -1)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + zaman) {
                if p.isRunning { bayrak.asim = true; p.terminate() }
            }
        }
        try? fh.close()
        let cikti = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return Sonuc(kod: kod, cikti: cikti, zamanAsimi: bayrak.asim)
    }
}

// MARK: - Bulut sağlayıcılar (OpenAI uyumlu)
struct BulutSaglayici {
    let ad: String
    let adres: URL
    let model: String
    let anahtar: String
    let ek: [String: Any]

    static func liste() -> [BulutSaglayici] {
        let ev = NSHomeDirectory() + "/Alex"
        var l: [BulutSaglayici] = []
        if let v = try? Data(contentsOf: URL(fileURLWithPath: ev + "/data/ai-keys.json")),
           let j = try? JSONSerialization.jsonObject(with: v) as? [String: Any],
           let k = j["groq"] as? String, !k.isEmpty {
            l.append(BulutSaglayici(ad: "Groq", adres: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                                    model: "openai/gpt-oss-120b", anahtar: k, ek: ["reasoning_effort": "medium"]))
        }
        if let k = try? String(contentsOfFile: ev + "/.evren-key", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !k.isEmpty {
            l.append(BulutSaglayici(ad: "EVREN", adres: URL(string: "https://evren-llmapi.ssyz.org.tr/v1/chat/completions")!,
                                    model: "qwen3.8-flash-next", anahtar: k, ek: [:]))
        }
        return l
    }
}
