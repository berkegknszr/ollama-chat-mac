import SwiftUI
import AppKit

@main
struct OllamaSohbetApp: App {
    @State private var depo = Depo()
    var body: some Scene {
        WindowGroup("Ollama Sohbet") {
            AnaGorunum()
                .environment(depo)
                .frame(minWidth: 760, minHeight: 520)
                .task { await depo.baslat() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await depo.modelleriYenile() }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni Sohbet") { depo.yeniSohbet() }.keyboardShortcut("n")
            }
        }
        Settings { AyarlarGorunum().environment(depo) }
    }
}

// MARK: - Ana pencere
struct AnaGorunum: View {
    @Environment(Depo.self) private var depo
    @State private var modelSayfasi = false

    var body: some View {
        @Bindable var depo = depo
        NavigationSplitView {
            List(selection: $depo.seciliID) {
                ForEach(depo.gruplar, id: \.0) { baslik, liste in
                    Section(baslik) {
                        ForEach(liste) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.baslik).lineLimit(1)
                                Text(modelAdi(s.model)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.vertical, 2)
                            .tag(s.id)
                            .contextMenu {
                                Button("Sil", role: .destructive) { depo.sil(s.id) }
                            }
                        }
                    }
                }
            }
            .onDeleteCommand { if let id = depo.seciliID { depo.sil(id) } }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
            .safeAreaInset(edge: .bottom) {
                Button { modelSayfasi = true } label: {
                    Label("Modeller", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(12)
            }
            .toolbar {
                ToolbarItem {
                    Button { depo.yeniSohbet() } label: { Label("Yeni sohbet", systemImage: "square.and.pencil") }
                        .help("Yeni sohbet (⌘N)")
                }
            }
        } detail: {
            SohbetGorunum()
        }
        .sheet(isPresented: $modelSayfasi) { ModelSayfasi().environment(depo) }
    }
}

// MARK: - Sohbet
struct SohbetGorunum: View {
    @Environment(Depo.self) private var depo
    @State private var metin = ""
    @FocusState private var odak: Bool

    var body: some View {
        @Bindable var depo = depo
        VStack(spacing: 0) {
            if depo.sunucuAcik == false {
                SunucuKapali()
            } else if let s = depo.seciliSohbet, !s.mesajlar.isEmpty {
                MesajListesi(sohbet: s)
            } else {
                BosDurum()
            }
            if let h = depo.hata {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(h).font(.callout)
                    Spacer()
                    Button { depo.hata = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .frame(maxWidth: 820)
            }
            yazici
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(depo.seciliSohbet?.baslik ?? "Ollama Sohbet")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Model", selection: Binding(get: { depo.etkinModel }, set: { depo.modelSec($0) })) {
                    Text(modelAdi(UZMAN)).tag(UZMAN)
                    Divider()
                    ForEach(depo.sohbetModelleri) { m in Text(m.name).tag(m.name) }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 140)
                .help("Model seç")
            }
            ToolbarItem(placement: .primaryAction) {
                if depo.dusunebilir(depo.etkinModel) {
                    Toggle(isOn: $depo.dusunme) { Label("Düşünme", systemImage: "brain") }
                        .toggleStyle(.button)
                        .help(depo.dusunme ? "Düşünme açık: daha yavaş, daha dikkatli" : "Düşünme kapalı: hızlı cevap")
                }
            }
        }
        .onAppear { odak = true }
        .onChange(of: depo.seciliID) { odak = true }
        .sheet(item: Binding(get: { depo.kodOnay }, set: { if $0 == nil { depo.kodOnayla(false) } })) { o in
            KodOnayGorunum(onay: o)
        }
    }

    private var yazici: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Mesaj yaz…  (yeni satır: ⌥↩)", text: $metin, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...10)
                .focused($odak)
                .onSubmit(gonder)
                .padding(.vertical, 6)
                .padding(.leading, 6)
            Button {
                depo.akiyor ? depo.durdur() : gonder()
            } label: {
                Image(systemName: depo.akiyor ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(gonderilebilir || depo.akiyor ? Color.accentColor : Color.secondary)
            .disabled(!gonderilebilir && !depo.akiyor)
            .help(depo.akiyor ? "Durdur (esc)" : "Gönder (↩)")
            Button("") { depo.durdur() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .padding(16)
        .frame(maxWidth: 820)
    }

    private var gonderilebilir: Bool {
        !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !depo.akiyor && !depo.etkinModel.isEmpty
    }

    private func gonder() {
        guard gonderilebilir else { return }
        depo.gonder(metin)
        metin = ""
        odak = true
    }
}

struct MesajListesi: View {
    @Environment(Depo.self) private var depo
    let sohbet: Sohbet

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(sohbet.mesajlar) { m in
                        MesajBalonu(
                            mesaj: m,
                            sonMu: m.id == sohbet.mesajlar.last?.id,
                            akiyor: depo.akanSohbetID == sohbet.id && m.id == sohbet.mesajlar.last?.id
                        )
                        .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("son")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo("son", anchor: .bottom) }
            .onChange(of: sohbet.id) { proxy.scrollTo("son", anchor: .bottom) }
            .onChange(of: (sohbet.mesajlar.last?.icerik.count ?? 0) + (sohbet.mesajlar.last?.dusunce.count ?? 0) + sohbet.mesajlar.count) {
                proxy.scrollTo("son", anchor: .bottom)
            }
        }
    }
}

struct MesajBalonu: View {
    @Environment(Depo.self) private var depo
    let mesaj: Mesaj
    let sonMu: Bool
    let akiyor: Bool
    @State private var dusunceAcik = false
    @State private var uzerinde = false

    var body: some View {
        if mesaj.rol == "user" {
            HStack {
                Spacer(minLength: 80)
                Text(mesaj.icerik)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !mesaj.dusunce.isEmpty {
                    DisclosureGroup(isExpanded: $dusunceAcik) {
                        Text(mesaj.dusunce.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 2) }
                            .padding(.top, 4)
                    } label: {
                        Label(akiyor && mesaj.icerik.isEmpty ? "Düşünüyor…" : "Düşünce", systemImage: "brain")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let a = mesaj.araclar, !a.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(a.enumerated()), id: \.offset) { _, t in
                            Text(t).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if mesaj.icerik.isEmpty && akiyor {
                    if mesaj.dusunce.isEmpty { ProgressView().controlSize(.small) }
                } else {
                    IcerikGorunum(metin: mesaj.icerik)
                }
                if !akiyor {
                    HStack(spacing: 12) {
                        Button { panoyaKopyala(mesaj.icerik) } label: { Image(systemName: "doc.on.doc") }
                            .help("Kopyala")
                        if sonMu {
                            Button { depo.yenidenUret() } label: { Image(systemName: "arrow.clockwise") }
                                .help("Yeniden üret")
                        }
                        if let b = mesaj.bilgi { Text(b).monospacedDigit() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(uzerinde || sonMu ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { uzerinde = $0 }
        }
    }
}

// MARK: - Markdown
struct IcerikGorunum: View {
    let metin: String

    private struct Blok: Identifiable { let id: Int; let kod: Bool; let dil: String; let metin: String }

    private var bloklar: [Blok] {
        metin.components(separatedBy: "```").enumerated().compactMap { i, p in
            if i % 2 == 1 {
                var satirlar = p.components(separatedBy: "\n")
                let dil = satirlar.isEmpty ? "" : satirlar.removeFirst().trimmingCharacters(in: .whitespaces)
                return Blok(id: i, kod: true, dil: dil, metin: satirlar.joined(separator: "\n").trimmingCharacters(in: .newlines))
            }
            let t = p.trimmingCharacters(in: .newlines)
            return t.isEmpty ? nil : Blok(id: i, kod: false, dil: "", metin: t)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(bloklar) { b in
                if b.kod { KodBlogu(dil: b.dil, kod: b.metin) }
                else { Text(Self.bicimle(b.metin)).textSelection(.enabled).lineSpacing(3) }
            }
        }
    }

    static func bicimle(_ s: String) -> AttributedString {
        var sonuc = AttributedString()
        let secenek = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let satirlar = s.components(separatedBy: "\n")
        for (i, ham) in satirlar.enumerated() {
            var satir = ham
            var font: Font?
            if let r = satir.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let seviye = satir[r].filter { $0 == "#" }.count
                satir.removeSubrange(r)
                font = seviye <= 2 ? .title3.bold() : .headline
            } else if let r = satir.range(of: #"^(\s*)[-*+]\s+"#, options: .regularExpression) {
                let girinti = String(satir[r].prefix { $0 == " " })
                satir.replaceSubrange(r, with: girinti + "•  ")
            } else if satir.trimmingCharacters(in: .whitespaces).range(of: #"^(-{3,}|\*{3,})$"#, options: .regularExpression) != nil {
                satir = "────────"
            }
            var parca = (try? AttributedString(markdown: satir, options: secenek)) ?? AttributedString(satir)
            if let font { parca.font = font }
            sonuc += parca
            if i < satirlar.count - 1 { sonuc += AttributedString("\n") }
        }
        return sonuc
    }
}

struct KodBlogu: View {
    let dil: String
    let kod: String
    @State private var kopyalandi = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dil.isEmpty ? "kod" : dil).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    panoyaKopyala(kod)
                    kopyalandi = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); kopyalandi = false }
                } label: {
                    Label(kopyalandi ? "Kopyalandı" : "Kopyala", systemImage: kopyalandi ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(kod)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

// MARK: - Durum ekranları
struct BosDurum: View {
    @Environment(Depo.self) private var depo
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("Ne konuşalım?").font(.title2.weight(.semibold))
            Text(depo.etkinModel.isEmpty ? "Önce bir model indir (Modeller)" : "\(depo.etkinModel) · bu Mac'te, internetsiz")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SunucuKapali: View {
    @Environment(Depo.self) private var depo
    @State private var basliyor = false
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "powerplug").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Ollama çalışmıyor").font(.title2.weight(.semibold))
            Text(depo.sunucu.absoluteString).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Tekrar dene") { Task { await depo.modelleriYenile() } }
                Button {
                    basliyor = true
                    Task { await depo.ollamaBaslat(); basliyor = false }
                } label: {
                    if basliyor { ProgressView().controlSize(.small) } else { Text("Ollama'yı başlat") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(basliyor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Modeller
struct ModelSayfasi: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var yeni = ""
    @State private var silinecek: ModelBilgi?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Modeller").font(.title2.bold())
                Spacer()
                Button("Bitti") { kapat() }.keyboardShortcut(.defaultAction)
            }
            List(depo.modeller) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(.body.weight(.medium))
                        Text([m.details?.parameter_size, m.details?.quantization_level,
                              ByteCountFormatter.string(fromByteCount: m.size, countStyle: .file)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !m.sohbetEder {
                        Text("gömme").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .help("Arama/RAG için; sohbet edemez")
                    }
                    if depo.dusunebilir(m.name) {
                        Image(systemName: "brain").foregroundStyle(.secondary).help("Düşünme destekli")
                    }
                    Button { silinecek = m } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Sil")
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("Model indir").font(.headline)
            HStack {
                TextField("ör. gemma3:4b, llama3.2, qwen3:14b", text: $yeni)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(indir)
                Button("İndir", action: indir)
                    .disabled(yeni.trimmingCharacters(in: .whitespaces).isEmpty || depo.indirme != nil)
            }
            if let ind = depo.indirme {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: ind.oran)
                    Text("\(ind.model): \(ind.durum)\(ind.oran.map { String(format: " · %%%.0f", $0 * 100) } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let h = depo.hata { Text(h).font(.caption).foregroundStyle(.red) }
            Link("Tüm modeller: ollama.com/library", destination: URL(string: "https://ollama.com/library")!)
                .font(.caption)
        }
        .padding(20)
        .frame(width: 540, height: 540)
        .confirmationDialog("Model silinsin mi?",
                            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }),
                            presenting: silinecek) { m in
            Button("\(m.name) modelini sil", role: .destructive) { Task { await depo.modelSil(m.name) } }
        } message: { m in
            Text("Diskten \(ByteCountFormatter.string(fromByteCount: m.size, countStyle: .file)) yer açılır. Tekrar indirmek gerekir.")
        }
    }

    private func indir() {
        let ad = yeni.trimmingCharacters(in: .whitespaces)
        guard !ad.isEmpty, depo.indirme == nil else { return }
        yeni = ""
        Task { await depo.modelIndir(ad) }
    }
}

// MARK: - Ayarlar
struct AyarlarGorunum: View {
    @AppStorage("sistem") private var sistem = ""
    @AppStorage("sicaklik") private var sicaklik = 0.7
    @AppStorage("baglam") private var baglam = 0
    @AppStorage("sunucu") private var sunucu = "http://localhost:11434"
    @AppStorage("araclar") private var araclar = true
    @AppStorage("kodOnaysiz") private var kodOnaysiz = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $sistem).font(.body).frame(height: 110)
            } header: {
                Text("Sistem talimatı")
            } footer: {
                Text("Her sohbetin başında modele verilir. Örn: \"Türkçe ve kısa cevap ver.\"")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Üretim") {
                LabeledContent("Sıcaklık") {
                    HStack {
                        Slider(value: $sicaklik, in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", sicaklik)).monospacedDigit().frame(width: 30)
                    }
                }
                Picker("Bağlam uzunluğu", selection: $baglam) {
                    Text("Model varsayılanı").tag(0)
                    Text("4K").tag(4096)
                    Text("8K").tag(8192)
                    Text("16K").tag(16384)
                    Text("32K").tag(32768)
                }
            }
            Section {
                Toggle("Araçlar (web araması, sayfa okuma, kod çalıştırma)", isOn: $araclar)
                Toggle("Kodu sormadan çalıştır", isOn: $kodOnaysiz).disabled(!araclar)
            } header: {
                Text("Araçlar")
            } footer: {
                Text("Araçları destekleyen modellerde ve Uzman modunda çalışır. Kod, geçici bir klasörde 30 sn sınırla çalışır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bağlantı") {
                TextField("Ollama adresi", text: $sunucu)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 580)
    }
}

struct KodOnayGorunum: View {
    @Environment(Depo.self) private var depo
    let onay: KodOnay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model bu kodu çalıştırmak istiyor (\(onay.dil))", systemImage: "terminal")
                .font(.headline)
            ScrollView {
                Text(onay.kod)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 160, maxHeight: 360)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Geçici bir klasörde, en fazla 30 saniye çalışır. Dosya silen ya da internete veri gönderen kodu reddet.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Reddet", role: .cancel) { depo.kodOnayla(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Çalıştır") { depo.kodOnayla(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
