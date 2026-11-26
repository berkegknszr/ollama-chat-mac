import SwiftUI
import AppKit

struct Mesaj: Identifiable, Codable, Equatable {
    var id = UUID()
    var rol: String
    var icerik: String
    var dusunce: String = ""
    var bilgi: String?
    var araclar: [String]?
}

struct Sohbet: Identifiable, Codable, Equatable {
    var id = UUID()
    var baslik = "Yeni sohbet"
    var model: String
    var mesajlar: [Mesaj] = []
    var guncelleme = Date()
}

struct ModelBilgi: Identifiable, Decodable, Hashable {
    var id: String { name }
    let name: String
    let size: Int64
    let details: Detay?
    struct Detay: Decodable, Hashable {
        let family: String?
        let parameter_size: String?
        let quantization_level: String?
    }
    var sohbetEder: Bool { !(details?.family ?? "").contains("bert") && !name.contains("embed") }
}

struct Indirme { var model: String; var durum: String; var oran: Double? }

struct Hata: LocalizedError {
    let mesaj: String
    init(_ m: String) { mesaj = m }
    var errorDescription: String? { mesaj }
}

@MainActor @Observable
final class Depo {
    var sohbetler: [Sohbet] = []
    var seciliID: UUID?
    var modeller: [ModelBilgi] = []
    var yetenekler: [String: [String]] = [:]
    var sunucuAcik: Bool?
    var akanGorev: Task<Void, Never>?
    var akanSohbetID: UUID?
    var hata: String?
    var indirme: Indirme?
    var kodOnay: KodOnay?
    private var onayDevam: CheckedContinuation<Bool, Never>?
    var dusunme: Bool = UserDefaults.standard.bool(forKey: "dusunme") {
        didSet { UserDefaults.standard.set(dusunme, forKey: "dusunme") }
    }
    var varsayilanModel: String = UserDefaults.standard.string(forKey: "model") ?? "" {
        didSet { UserDefaults.standard.set(varsayilanModel, forKey: "model") }
    }

    private let dosya: URL = {
        let k = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OllamaSohbet")
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k.appending(path: "sohbetler.json")
    }()

    var sunucu: URL {
        let s = UserDefaults.standard.string(forKey: "sunucu") ?? ""
        return URL(string: s.isEmpty ? "http://localhost:11434" : s) ?? URL(string: "http://localhost:11434")!
    }

    var sohbetModelleri: [ModelBilgi] { modeller.filter(\.sohbetEder) }
    var seciliSohbet: Sohbet? { sohbetler.first { $0.id == seciliID } }
    var akiyor: Bool { akanGorev != nil }
    var etkinModel: String { seciliSohbet.map { $0.model.isEmpty ? varsayilanModel : $0.model } ?? varsayilanModel }

    func dusunebilir(_ m: String) -> Bool { yetenekler[m]?.contains("thinking") ?? false }

    var gruplar: [(String, [Sohbet])] {
        let cal = Calendar.current
        let hafta = Date().addingTimeInterval(-7 * 86400)
        var g: [String: [Sohbet]] = [:]
        for s in sohbetler.sorted(by: { $0.guncelleme > $1.guncelleme }) {
            let k = cal.isDateInToday(s.guncelleme) ? "Bugün"
                : cal.isDateInYesterday(s.guncelleme) ? "Dün"
                : s.guncelleme > hafta ? "Son 7 gün" : "Daha eski"
            g[k, default: []].append(s)
        }
        return ["Bugün", "Dün", "Son 7 gün", "Daha eski"].compactMap { k in g[k].map { (k, $0) } }
    }

    // MARK: - Kalıcılık
    func baslat() async {
        if let v = try? Data(contentsOf: dosya), let s = try? JSONDecoder().decode([Sohbet].self, from: v) {
            sohbetler = s
        }
        seciliID = sohbetler.max(by: { $0.guncelleme < $1.guncelleme })?.id
        await modelleriYenile()
    }

    func kaydet() {
        if let v = try? JSONEncoder().encode(sohbetler) { try? v.write(to: dosya, options: .atomic) }
    }

    private func indeks(_ id: UUID?) -> Int? { sohbetler.firstIndex { $0.id == id } }

    // MARK: - Sohbetler
    func yeniSohbet() {
        if let s = seciliSohbet, s.mesajlar.isEmpty { return }
        let s = Sohbet(model: varsayilanModel)
        sohbetler.append(s)
        seciliID = s.id
    }

    func sil(_ id: UUID) {
        if akanSohbetID == id { durdur() }
        sohbetler.removeAll { $0.id == id }
        if seciliID == id { seciliID = sohbetler.max(by: { $0.guncelleme < $1.guncelleme })?.id }
        kaydet()
    }

    func modelSec(_ m: String) {
        varsayilanModel = m
        if let i = indeks(seciliID) { sohbetler[i].model = m }
    }

    func gonder(_ metin: String) {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, akanGorev == nil, !varsayilanModel.isEmpty || seciliSohbet?.model.isEmpty == false else { return }
        if seciliID == nil { yeniSohbet() }
        guard let i = indeks(seciliID) else { return }
        if sohbetler[i].model.isEmpty { sohbetler[i].model = varsayilanModel }
        sohbetler[i].mesajlar.append(Mesaj(rol: "user", icerik: t))
        if sohbetler[i].baslik == "Yeni sohbet" {
            sohbetler[i].baslik = String(t.replacingOccurrences(of: "\n", with: " ").prefix(48))
        }
        cevapla(sohbetler[i].id)
    }

    func yenidenUret() {
        guard akanGorev == nil, let i = indeks(seciliID), sohbetler[i].mesajlar.last?.rol == "assistant" else { return }
        sohbetler[i].mesajlar.removeLast()
        cevapla(sohbetler[i].id)
    }

    func durdur() {
        kodOnayla(false)
        akanGorev?.cancel()
    }

    private func cevapla(_ sid: UUID) {
        guard let i = indeks(sid) else { return }
        let sohbet = sohbetler[i]
        sohbetler[i].mesajlar.append(Mesaj(rol: "assistant", icerik: ""))
        sohbetler[i].guncelleme = Date()
        akanSohbetID = sid
        hata = nil

        let d = UserDefaults.standard
        let uzman = sohbet.model == UZMAN
        let araclarAcik = (d.object(forKey: "araclar") as? Bool ?? true)
            && (uzman || (yetenekler[sohbet.model]?.contains("tools") ?? false))
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy EEEE, HH:mm"
        var sistem = "Bugünün tarihi: \(f.string(from: Date())). Kullanıcıyla Türkçe konuş."
        if araclarAcik {
            sistem += """
             Eğitim bilgin eski olabilir: güncel olan ya da emin olmadığın her bilgi için web_ara aracını kullan, uydurma.
             Kod yazdığında, çalıştırılabiliyorsa önce kod_calistir ile küçük bir testle dene; hata varsa düzelt ve tekrar dene.
             Son cevapta test edilmiş kodu ver ve test edildiğini belirt.
            """
        }
        let kullanici = d.string(forKey: "sistem") ?? ""
        if !kullanici.isEmpty { sistem += "\n\n" + kullanici }
        var gecmis: [[String: Any]] = [["role": "system", "content": sistem]]
        gecmis += sohbet.mesajlar.map { ["role": $0.rol, "content": $0.icerik] }

        akanGorev = Task {
            do {
                for _ in 0..<8 {
                    let cagrilar = uzman
                        ? try await bulutTur(sid, gecmis, araclarAcik)
                        : try await ollamaTur(sid, sohbet.model, gecmis, araclarAcik)
                    if cagrilar.isEmpty { break }
                    if uzman {
                        gecmis.append(["role": "assistant", "content": "", "tool_calls": cagrilar.map {
                            ["id": $0.id, "type": "function", "function": ["name": $0.ad, "arguments": $0.hamArguman]] as [String: Any]
                        }])
                    } else {
                        gecmis.append(["role": "assistant", "content": "", "tool_calls": cagrilar.map {
                            ["function": ["name": $0.ad, "arguments": $0.argumanlar]] as [String: Any]
                        }])
                    }
                    for c in cagrilar {
                        try Task.checkCancellation()
                        degistir(sid) { $0.araclar = ($0.araclar ?? []) + [Araclar.durumMetni(c)] }
                        let sonuc = await araciCalistir(c)
                        var m: [String: Any] = ["role": "tool", "content": sonuc]
                        if uzman { m["tool_call_id"] = c.id } else { m["tool_name"] = c.ad }
                        gecmis.append(m)
                    }
                }
            } catch {
                let iptal = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !iptal {
                    hata = (error as? URLError) != nil && !uzman ? "Ollama'ya ulaşılamadı. Çalışıyor mu?" : error.localizedDescription
                }
            }
            if let j = indeks(sid), let son = sohbetler[j].mesajlar.last, son.rol == "assistant",
               son.icerik.isEmpty, son.dusunce.isEmpty, (son.araclar ?? []).isEmpty {
                sohbetler[j].mesajlar.removeLast()
            }
            akanGorev = nil
            akanSohbetID = nil
            kaydet()
        }
    }

    private func degistir(_ sid: UUID, _ f: (inout Mesaj) -> Void) {
        guard let j = indeks(sid), var son = sohbetler[j].mesajlar.last, son.rol == "assistant" else { return }
        f(&son)
        sohbetler[j].mesajlar[sohbetler[j].mesajlar.count - 1] = son
    }

    private func ollamaTur(_ sid: UUID, _ model: String, _ gecmis: [[String: Any]], _ araclar: Bool) async throws -> [AracCagrisi] {
        let d = UserDefaults.standard
        var secenek: [String: Any] = ["temperature": d.object(forKey: "sicaklik") as? Double ?? 0.7]
        let ctx = d.integer(forKey: "baglam")
        secenek["num_ctx"] = ctx > 0 ? ctx : (araclar ? 12288 : 8192)
        var govde: [String: Any] = ["model": model, "messages": gecmis, "stream": true, "options": secenek]
        if dusunebilir(model) { govde["think"] = dusunme }
        if araclar { govde["tools"] = Araclar.tanimlar }
        var istek = URLRequest(url: sunucu.appending(path: "api/chat"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = 900
        istek.httpBody = try JSONSerialization.data(withJSONObject: govde)

        let (bytes, yanit) = try await URLSession.shared.bytes(for: istek)
        if let h = yanit as? HTTPURLResponse, h.statusCode != 200 {
            var s = ""
            for try await l in bytes.lines { s += l }
            let e = (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])?["error"] as? String
            throw Hata(e ?? "Sunucu hatası (\(h.statusCode))")
        }
        var cagrilar: [AracCagrisi] = []
        for try await satir in bytes.lines {
            guard let p = try? JSONSerialization.jsonObject(with: Data(satir.utf8)) as? [String: Any] else { continue }
            if let e = p["error"] as? String { throw Hata(e) }
            let m = p["message"] as? [String: Any] ?? [:]
            for tc in m["tool_calls"] as? [[String: Any]] ?? [] {
                guard let fn = tc["function"] as? [String: Any], let ad = fn["name"] as? String else { continue }
                let arg = fn["arguments"] as? [String: Any] ?? [:]
                let ham = (try? JSONSerialization.data(withJSONObject: arg)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                cagrilar.append(AracCagrisi(id: UUID().uuidString, ad: ad, argumanlar: arg, hamArguman: ham))
            }
            degistir(sid) { son in
                son.icerik += m["content"] as? String ?? ""
                son.dusunce += m["thinking"] as? String ?? ""
                if p["done"] as? Bool == true, let n = p["eval_count"] as? Int, let t = p["eval_duration"] as? Int, t > 0 {
                    son.bilgi = String(format: "%d token · %.1f token/sn", n, Double(n) / (Double(t) / 1e9))
                }
            }
        }
        return cagrilar
    }

    private func bulutTur(_ sid: UUID, _ gecmis: [[String: Any]], _ araclar: Bool) async throws -> [AracCagrisi] {
        let liste = BulutSaglayici.liste()
        guard !liste.isEmpty else { throw Hata("Uzman modu için bulut anahtarı bulunamadı (~/Alex/data/ai-keys.json).") }
        var sonHata = "Bulut modeline ulaşılamadı."
        for s in liste {
            var govde: [String: Any] = ["model": s.model, "messages": gecmis, "stream": true]
            for (k, v) in s.ek { govde[k] = v }
            if araclar { govde["tools"] = Araclar.tanimlar }
            var istek = URLRequest(url: s.adres)
            istek.httpMethod = "POST"
            istek.timeoutInterval = 300
            istek.setValue("Bearer \(s.anahtar)", forHTTPHeaderField: "Authorization")
            istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
            istek.httpBody = try JSONSerialization.data(withJSONObject: govde)
            let bytes: URLSession.AsyncBytes
            do {
                let (b, yanit) = try await URLSession.shared.bytes(for: istek)
                if let h = yanit as? HTTPURLResponse, h.statusCode != 200 {
                    sonHata = "\(s.ad) hata verdi (\(h.statusCode))."
                    continue
                }
                bytes = b
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                sonHata = "\(s.ad): \(error.localizedDescription)"
                continue
            }
            var parcalar: [Int: (id: String, ad: String, arg: String)] = [:]
            for try await satir in bytes.lines {
                guard satir.hasPrefix("data:") else { continue }
                let veri = satir.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if veri == "[DONE]" { break }
                guard let j = try? JSONSerialization.jsonObject(with: Data(veri.utf8)) as? [String: Any] else { continue }
                if let e = j["error"] as? [String: Any] { throw Hata(e["message"] as? String ?? "Bulut hatası") }
                let secim = (j["choices"] as? [[String: Any]])?.first ?? [:]
                let delta = secim["delta"] as? [String: Any] ?? [:]
                for tc in delta["tool_calls"] as? [[String: Any]] ?? [] {
                    let ix = tc["index"] as? Int ?? 0
                    var p = parcalar[ix] ?? (id: "", ad: "", arg: "")
                    if let id = tc["id"] as? String { p.id = id }
                    let fn = tc["function"] as? [String: Any] ?? [:]
                    if let ad = fn["name"] as? String { p.ad += ad }
                    if let a = fn["arguments"] as? String { p.arg += a }
                    parcalar[ix] = p
                }
                let icerik = delta["content"] as? String ?? ""
                let dus = (delta["reasoning"] as? String) ?? (delta["reasoning_content"] as? String) ?? ""
                if !icerik.isEmpty || !dus.isEmpty {
                    degistir(sid) { $0.icerik += icerik; $0.dusunce += dus }
                }
            }
            degistir(sid) { $0.bilgi = "Uzman · \(s.ad) · \(s.model)" }
            return parcalar.keys.sorted().compactMap { k in
                guard let p = parcalar[k], !p.ad.isEmpty else { return nil }
                let arg = (try? JSONSerialization.jsonObject(with: Data((p.arg.isEmpty ? "{}" : p.arg).utf8)) as? [String: Any]) ?? [:]
                return AracCagrisi(id: p.id.isEmpty ? UUID().uuidString : p.id, ad: p.ad, argumanlar: arg,
                                   hamArguman: p.arg.isEmpty ? "{}" : p.arg)
            }
        }
        throw Hata(sonHata)
    }

    private func araciCalistir(_ c: AracCagrisi) async -> String {
        let a = c.argumanlar
        switch c.ad {
        case "web_ara": return await Araclar.webAra(a["sorgu"] as? String ?? "")
        case "sayfa_oku": return await Araclar.sayfaOku(a["url"] as? String ?? "")
        case "kod_calistir":
            let dil = a["dil"] as? String ?? "python"
            let kod = a["kod"] as? String ?? ""
            guard !kod.isEmpty else { return "Kod boş." }
            if !UserDefaults.standard.bool(forKey: "kodOnaysiz") {
                let izin = await withCheckedContinuation { devam in
                    onayDevam = devam
                    kodOnay = KodOnay(dil: dil, kod: kod)
                }
                guard izin else { return "Kullanıcı kodun çalıştırılmasını reddetti. Kodu çalıştırmadan devam et." }
            }
            return await Araclar.kodCalistir(dil: dil, kod: kod)
        default: return "Bilinmeyen araç: \(c.ad)"
        }
    }

    func kodOnayla(_ izin: Bool) {
        kodOnay = nil
        let d = onayDevam
        onayDevam = nil
        d?.resume(returning: izin)
    }

    // MARK: - Modeller
    func modelleriYenile() async {
        struct R: Decodable { let models: [ModelBilgi] }
        do {
            let (v, _) = try await URLSession.shared.data(from: sunucu.appending(path: "api/tags"))
            modeller = try JSONDecoder().decode(R.self, from: v).models.sorted { $0.name < $1.name }
            sunucuAcik = true
            if varsayilanModel != UZMAN, !sohbetModelleri.contains(where: { $0.name == varsayilanModel }) {
                varsayilanModel = sohbetModelleri.first?.name ?? ""
            }
            for m in sohbetModelleri where yetenekler[m.name] == nil {
                struct S: Decodable { let capabilities: [String]? }
                var istek = URLRequest(url: sunucu.appending(path: "api/show"))
                istek.httpMethod = "POST"
                istek.httpBody = try? JSONSerialization.data(withJSONObject: ["model": m.name])
                if let (v, _) = try? await URLSession.shared.data(for: istek),
                   let s = try? JSONDecoder().decode(S.self, from: v) {
                    yetenekler[m.name] = s.capabilities ?? []
                }
            }
        } catch {
            sunucuAcik = false
        }
    }

    func ollamaBaslat() async {
        let yollar = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
        guard let yol = yollar.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            hata = "Ollama bulunamadı. brew install ollama ile kur."
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yol)
        p.arguments = ["serve"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            await modelleriYenile()
            if sunucuAcik == true { hata = nil; return }
        }
    }

    func modelIndir(_ ad: String) async {
        struct P: Decodable { let status: String?; let completed: Int64?; let total: Int64?; let error: String? }
        indirme = Indirme(model: ad, durum: "Başlıyor…", oran: nil)
        hata = nil
        var istek = URLRequest(url: sunucu.appending(path: "api/pull"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = 7200
        istek.httpBody = try? JSONSerialization.data(withJSONObject: ["model": ad, "stream": true])
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: istek)
            for try await satir in bytes.lines {
                guard let p = try? JSONDecoder().decode(P.self, from: Data(satir.utf8)) else { continue }
                if let e = p.error { throw Hata(e) }
                var oran: Double?
                if let c = p.completed, let t = p.total, t > 0 { oran = Double(c) / Double(t) }
                indirme?.durum = p.status ?? ""
                indirme?.oran = oran
            }
        } catch {
            hata = "İndirme başarısız: \(error.localizedDescription)"
        }
        indirme = nil
        await modelleriYenile()
    }

    func modelSil(_ ad: String) async {
        var istek = URLRequest(url: sunucu.appending(path: "api/delete"))
        istek.httpMethod = "DELETE"
        istek.httpBody = try? JSONSerialization.data(withJSONObject: ["model": ad])
        _ = try? await URLSession.shared.data(for: istek)
        await modelleriYenile()
    }
}

func panoyaKopyala(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
