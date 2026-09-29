import Foundation
import Core

/// One recorded client signature (in-person signing in the app, or read
/// back from a signed copy). The image is only ever a PNG data URL the
/// app produced or validated.
public struct AgreementSignature: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable { case drawn, typed }
    public var typedName: String
    public var title: String
    public var method: Method
    public var imageDataURL: String?
    public var signedAtLabel: String
    public var signedAtISO: String
    public var device: String

    public init(typedName: String, title: String, method: Method, imageDataURL: String?, signedAtLabel: String, signedAtISO: String, device: String) {
        self.typedName = typedName
        self.title = title
        self.method = method
        self.imageDataURL = imageDataURL
        self.signedAtLabel = signedAtLabel
        self.signedAtISO = signedAtISO
        self.device = device
    }

    /// Accepts only a PNG data URL of reasonable size.
    public static func isSafeImage(_ url: String?) -> Bool {
        guard let url else { return true }
        return url.hasPrefix("data:image/png;base64,") && url.count < 1_500_000
            && url.dropFirst("data:image/png;base64,".count).allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    }
}

/// HTML for the engagement agreement in three forms: the interactive
/// signing page (a single self-contained file — no network, no external
/// scripts, fonts, or images), a static review copy, and the final signed
/// copy. Every piece of user-entered text is HTML-escaped.
public enum EngagementAgreementHTML {
    public enum Mode: Sendable {
        case signing
        case review
        case signed(AgreementSignature)
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// `providerSignedOn` is the date the bookkeeper signed (at preparation).
    /// `pdfFontCSS` is extra CSS (local @font-face) used only for PDF output.
    public static func render(_ a: EngagementAgreement, mode: Mode, providerSignedOn: AccountingDate, pdfFontCSS: String = "") -> String {
        let T = EngagementAgreementTemplate.self
        let docID = T.documentID(a)
        let isSigning: Bool = { if case .signing = mode { return true }; return false }()

        let fees = T.feeSummary(a).map { "<tr><th>\(esc($0.label))</th><td>\(esc($0.value))</td></tr>" }.joined()
        let sections = T.sections(a).map { s -> String in
            let body = s.blocks.map { b -> String in
                switch b {
                case .paragraph(let p): return "<p>\(esc(p))</p>"
                case .conspicuous(let p): return "<p class=\"conspicuous\">\(esc(p))</p>"
                case .bullets(let items): return "<ul>" + items.map { "<li>\(esc($0))</li>" }.joined() + "</ul>"
                case .labeled(let l, let p): return "<p><b>\(esc(l))</b> \(esc(p))</p>"
                }
            }.joined()
            return "<section class=\"clause\"><h2><span class=\"n\">\(s.number).</span> \(esc(s.title))</h2>\(body)</section>"
        }.joined()

        let providerDate = T.longDate(providerSignedOn)
        let provider = """
        <div class="party">
          <div class="plabel">Bookkeeper</div>
          <div class="pname">\(esc(a.firm.firmName))</div>
          <div class="sigline"><span class="script">\(esc(a.firm.ownerName))</span></div>
          <div class="meta">\(esc(a.firm.ownerName)), \(esc(a.firm.ownerTitle)) · signed electronically \(esc(providerDate))</div>
          <div class="meta">\(esc(a.firm.email)) · \(esc(a.firm.phone))</div>
        </div>
        """

        let clientParty: String
        switch mode {
        case .review:
            clientParty = """
            <div class="party">
              <div class="plabel">Client</div>
              <div class="pname">\(esc(a.client.legalName))</div>
              <div class="sigline blank"></div>
              <div class="meta">Signature</div>
              <div class="fillrow"><span>Printed name</span><span class="fill">\(esc(a.client.contactName))</span></div>
              <div class="fillrow"><span>Title</span><span class="fill">\(esc(a.client.contactTitle))</span></div>
              <div class="fillrow"><span>Date</span><span class="fill"></span></div>
              <div class="meta">\(esc(a.client.contactEmail))</div>
            </div>
            """
        case .signed(let sig):
            let mark = sig.method == .drawn && AgreementSignature.isSafeImage(sig.imageDataURL) && sig.imageDataURL != nil
                ? "<img class=\"sigimg\" alt=\"Signature\" src=\"\(sig.imageDataURL!)\">"
                : "<span class=\"script\">\(esc(sig.typedName))</span>"
            clientParty = """
            <div class="party">
              <div class="plabel">Client</div>
              <div class="pname">\(esc(a.client.legalName))</div>
              <div class="sigline">\(mark)</div>
              <div class="meta">\(esc(sig.typedName))\(sig.title.isEmpty ? "" : ", \(esc(sig.title))") · signed electronically \(esc(sig.signedAtLabel))</div>
              <div class="meta">\(esc(a.client.contactEmail))</div>
            </div>
            """
        case .signing:
            clientParty = """
            <div class="party" id="clientParty">
              <div class="plabel">Client</div>
              <div class="pname">\(esc(a.client.legalName))</div>
              <div class="sigline" id="sigDisplay"></div>
              <div class="meta" id="sigMeta">Not yet signed</div>
              <div class="meta">\(esc(a.client.contactEmail))</div>
            </div>
            """
        }

        var certificate = ""
        if case .signed(let sig) = mode {
            certificate = """
            <section class="cert">
              <h3>Signature certificate</h3>
              <table>
                <tr><th>Document ID</th><td>\(esc(docID))</td></tr>
                <tr><th>Signed by</th><td>\(esc(sig.typedName))\(sig.title.isEmpty ? "" : ", \(esc(sig.title))"), for \(esc(a.client.legalName))</td></tr>
                <tr><th>Method</th><td>\(sig.method == .drawn ? "Drawn electronic signature with typed legal name" : "Typed legal name as electronic signature")</td></tr>
                <tr><th>Signed at</th><td>\(esc(sig.signedAtLabel)) (\(esc(sig.signedAtISO)))</td></tr>
                <tr><th>Device</th><td>\(esc(sig.device))</td></tr>
                <tr><th>Consent</th><td>Client agreed to sign and receive records electronically.</td></tr>
                <tr><th>Template</th><td>\(esc(T.version))</td></tr>
              </table>
            </section>
            """
        }

        let signingPanel = isSigning ? signingPanelHTML(a, docID: docID) : ""
        let script = isSigning ? signingScript(a, docID: docID) : ""

        return """
        <!DOCTYPE html>
        <html lang="en"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="document-id" content="\(esc(docID))">
        <title>\(esc(T.title)) — \(esc(a.client.legalName))</title>
        <style>\(css(firm: a.firm, docID: docID))\(pdfFontCSS)</style>
        </head><body>
        \(isSigning ? "<noscript><div class=\"banner warn\">To sign, open this file in a web browser such as Safari, Chrome, or Edge with JavaScript turned on. You can also print it, sign by hand, and return a scan or photo.</div></noscript>" : "")
        <main class="doc">
          <header class="mast">
            <div class="firm">\(esc(a.firm.firmName))</div>
            <div class="contact">\(esc(a.firm.city)), \(esc(a.firm.state)) · \(esc(a.firm.phone)) · \(esc(a.firm.email))</div>
            <h1>\(esc(T.title))</h1>
            <div class="sub">Prepared for <b>\(esc(a.client.legalName))</b>\(a.client.contactName.isEmpty ? "" : " · Attention: \(esc(a.client.contactName))")</div>
            <div class="docid">Document ID \(esc(docID)) · Template \(esc(T.version))</div>
          </header>
          <p class="preamble">\(esc(T.preamble(a)))</p>
          <section class="fees keep">
            <h2>Agreed Services and Fees</h2>
            <table>\(fees)</table>
          </section>
          \(sections)
          <section class="signatures keep">
            <h2>Signatures</h2>
            <p>By signing, each party confirms that it has read and agrees to this Agreement, including the fees, the services not included, and the limitation of liability.</p>
            <div class="parties">\(clientParty)\(provider)</div>
          </section>
          \(certificate)
          \(signingPanel)
          <footer class="endnote">\(esc(a.firm.firmName)) · \(esc(T.title)) · Document ID \(esc(docID))</footer>
        </main>
        \(script)
        </body></html>
        """
    }

    static func css(firm: FirmProfile, docID: String) -> String {
        """
        :root{--navy:#1B2A4A;--teal:#1F8A8A;--gold:#C9A227;--ink:#1B2A4A;--muted:#56637A;--line:#DDE3EB;--soft:#F4F7FA;--neg:#B23A48}
        *{box-sizing:border-box}
        html{-webkit-text-size-adjust:100%}
        body{margin:0;background:#EEF2F6;color:var(--ink);font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55}
        .doc{max-width:820px;margin:24px auto;background:#fff;padding:44px 52px;border-radius:10px;box-shadow:0 2px 18px rgba(27,42,74,.10)}
        .mast{border-top:5px solid var(--navy);padding-top:14px;margin-bottom:14px}
        .firm{font-size:12px;font-weight:700;letter-spacing:1.6px;text-transform:uppercase;color:var(--teal)}
        .contact{font-size:12px;color:var(--muted);margin-top:2px}
        h1{font-size:28px;line-height:1.2;margin:12px 0 4px;letter-spacing:-.3px}
        .sub{font-size:15px}
        .docid{font-size:11.5px;color:var(--muted);margin-top:6px;font-variant-numeric:tabular-nums}
        .preamble{margin:14px 0 18px}
        h2{font-size:17px;margin:22px 0 8px;padding-bottom:4px;border-bottom:1.5px solid var(--navy);break-after:avoid;page-break-after:avoid}
        h2 .n{color:var(--gold);margin-right:4px}
        h3{font-size:15px;margin:0 0 8px}
        p{margin:0 0 9px}
        ul{margin:0 0 10px;padding-left:22px}
        li{margin:0 0 5px}
        .conspicuous{font-weight:700;font-size:13.5px;letter-spacing:.1px}
        .fees{background:var(--soft);border:1px solid var(--line);border-left:4px solid var(--teal);border-radius:8px;padding:6px 16px 10px}
        .fees h2{border:0;margin:8px 0 4px}
        .fees table{width:100%;border-collapse:collapse}
        .fees th{text-align:left;font-weight:600;padding:7px 12px 7px 0;width:38%;vertical-align:top;border-top:1px solid var(--line)}
        .fees td{padding:7px 0;border-top:1px solid var(--line)}
        .fees tr:first-child th,.fees tr:first-child td{border-top:0}
        .parties{display:flex;gap:28px;margin-top:10px}
        .party{flex:1;min-width:0;border:1px solid var(--line);border-radius:8px;padding:12px 14px}
        .plabel{font-size:11px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:var(--teal)}
        .pname{font-weight:700;margin:2px 0 6px}
        .sigline{min-height:62px;border-bottom:1.5px solid var(--navy);display:flex;align-items:flex-end;padding-bottom:4px}
        .sigline.blank{min-height:56px}
        .script{font-family:"Snell Roundhand","Apple Chancery","Segoe Script","Brush Script MT","Lucida Handwriting",cursive;font-size:30px;line-height:1.1;color:#14305a}
        .sigimg{max-height:70px;max-width:100%}
        .meta{font-size:12px;color:var(--muted);margin-top:5px}
        .fillrow{display:flex;gap:8px;font-size:12.5px;margin-top:10px}
        .fillrow span:first-child{width:92px;color:var(--muted)}
        .fill{flex:1;border-bottom:1px solid var(--muted);min-height:18px}
        .cert{margin-top:22px;border:1px solid var(--line);border-radius:8px;padding:12px 16px;background:var(--soft)}
        .cert table{border-collapse:collapse;font-size:12.5px;width:100%}
        .cert th{text-align:left;color:var(--muted);font-weight:600;padding:3px 12px 3px 0;width:120px;vertical-align:top}
        .cert td{padding:3px 0}
        .endnote{margin-top:26px;font-size:11px;color:var(--muted);border-top:1px solid var(--line);padding-top:8px}
        .banner{max-width:820px;margin:16px auto 0;padding:12px 16px;border-radius:8px;font-size:14px}
        .banner.warn{background:#FBF1D9;color:#6E5812;border:1px solid var(--gold)}
        .panel{margin-top:22px;border:2px solid var(--teal);border-radius:10px;padding:18px 18px 16px;background:#F6FBFB}
        .panel h2{border:0;margin:0 0 4px}
        .panel .hint{font-size:13px;color:var(--muted);margin-bottom:12px}
        .field{margin:0 0 12px}
        .field label{display:block;font-size:12.5px;font-weight:600;margin-bottom:4px}
        .field input[type=text]{width:100%;font:inherit;padding:10px 12px;border:1px solid #B8C3D1;border-radius:8px;background:#fff}
        .row2{display:flex;gap:14px}.row2 .field{flex:1}
        .tabs{display:flex;gap:6px;margin:4px 0 10px}
        .tab{font:inherit;font-size:14px;padding:8px 14px;border-radius:999px;border:1px solid #B8C3D1;background:#fff;color:var(--ink);cursor:pointer}
        .tab.on{background:var(--navy);border-color:var(--navy);color:#fff}
        .pad-wrap{position:relative;border:1.5px dashed #9AA5B4;border-radius:8px;background:#fff;height:170px;touch-action:none}
        #pad{width:100%;height:100%;display:block;touch-action:none;cursor:crosshair;border-radius:8px}
        .pad-hint{position:absolute;left:14px;bottom:10px;font-size:12px;color:#9AA5B4;pointer-events:none}
        .typed-preview{border:1.5px dashed #9AA5B4;border-radius:8px;background:#fff;min-height:90px;display:flex;align-items:center;padding:8px 16px}
        .check{display:flex;gap:10px;align-items:flex-start;font-size:13.5px;margin:12px 0}
        .check input{margin-top:3px;width:18px;height:18px;flex:none}
        .btns{display:flex;flex-wrap:wrap;gap:10px;margin-top:6px}
        .btn{font:inherit;font-size:15px;font-weight:600;padding:11px 18px;border-radius:8px;border:1px solid var(--navy);background:#fff;color:var(--navy);cursor:pointer}
        .btn.primary{background:var(--teal);border-color:var(--teal);color:#fff}
        .btn:disabled{opacity:.45;cursor:not-allowed}
        .err{color:var(--neg);font-size:13px;min-height:18px;margin-top:6px}
        .done{border:2px solid var(--teal);background:#E3F2F2;border-radius:10px;padding:14px 16px;margin-top:14px}
        .done b{color:#135E5E}
        [hidden]{display:none!important}
        @media (max-width:640px){
          .doc{margin:0;border-radius:0;padding:22px 16px;box-shadow:none}
          body{font-size:15.5px}
          h1{font-size:23px}
          .parties,.row2{flex-direction:column;gap:12px}
          .fees th{width:auto;display:block;padding-bottom:0;border:0}
          .fees td{display:block;padding-top:2px}
          .fees tr{display:block;border-top:1px solid var(--line);padding:6px 0}
          .fees tr:first-child{border-top:0}
        }
        @page{size:Letter;margin:0.7in 0.7in 0.8in 0.7in;
          @bottom-left{content:"\(esc(firm.firmName)) · Document ID \(esc(docID))";font:500 7.5pt Inter,Helvetica,sans-serif;color:#56637A}
          @bottom-right{content:"Page " counter(page) " of " counter(pages);font:500 7.5pt Inter,Helvetica,sans-serif;color:#56637A}}
        @media print{
          body{background:#fff;font-size:10.5pt}
          .doc{margin:0;max-width:none;padding:0;box-shadow:none;border-radius:0}
          .panel,.banner,.noprint{display:none!important}
          h2{font-size:12pt}
          .keep,.party,.cert{break-inside:avoid;page-break-inside:avoid}
          li,p{orphans:3;widows:3}
        }
        """
    }

    static func signingPanelHTML(_ a: EngagementAgreement, docID: String) -> String {
        """
        <section class="panel" id="panel">
          <h2>Review and sign</h2>
          <div class="hint">Read the full agreement above. Type your full legal name, then either draw your signature or use your typed name as your signature.</div>
          <div class="row2">
            <div class="field"><label for="typedName">Full legal name (required)</label><input type="text" id="typedName" autocomplete="name" value="\(esc(a.client.contactName))"></div>
            <div class="field"><label for="title">Title</label><input type="text" id="title" autocomplete="organization-title" value="\(esc(a.client.contactTitle))" placeholder="Owner, Managing Member…"></div>
          </div>
          <div class="field"><label>Signature</label>
            <div class="tabs" role="tablist">
              <button type="button" class="tab on" id="tabType" role="tab">Use typed name</button>
              <button type="button" class="tab" id="tabDraw" role="tab">Draw signature</button>
            </div>
            <div id="typedBox" class="typed-preview"><span class="script" id="typedPreview"></span></div>
            <div id="drawBox" hidden>
              <div class="pad-wrap"><canvas id="pad" aria-label="Signature pad"></canvas><div class="pad-hint" id="padHint">Sign here with your mouse, finger, or stylus</div></div>
              <div class="btns"><button type="button" class="btn" id="clearPad">Clear signature</button></div>
            </div>
          </div>
          <label class="check"><input type="checkbox" id="consent"><span>I agree to sign this Agreement electronically and to receive records and notices from \(esc(a.firm.firmName)) electronically. I understand my electronic signature is legally binding, the same as a handwritten one.</span></label>
          <label class="check"><input type="checkbox" id="authority"><span>I am authorized to sign on behalf of \(esc(a.client.legalName)).</span></label>
          <div class="field"><label>Date signed</label><input type="text" id="dateSigned" readonly></div>
          <div class="btns"><button type="button" class="btn primary" id="accept">Accept &amp; Sign Agreement</button><button type="button" class="btn" id="printBlank">Print this agreement</button></div>
          <div class="err" id="err" role="alert"></div>
        </section>
        <section class="done noprint" id="done" hidden>
          <p><b>Signed.</b> <span id="doneText"></span></p>
          <p id="returnText">Next: save your signed copy as a PDF and email it to <a href="mailto:\(esc(a.firm.email))?subject=\(esc(("Signed agreement — " + a.client.legalName).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))">\(esc(a.firm.email))</a>. On the print screen, choose <i>Save as PDF</i>.</p>
          <div class="btns"><button type="button" class="btn primary" id="printSigned">Save signed copy as PDF</button></div>
        </section>
        """
    }

    static func signingScript(_ a: EngagementAgreement, docID: String) -> String {
        """
        <script>
        (function () {
          "use strict";
          var $ = function (id) { return document.getElementById(id); };
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vlAgreement;
          var mode = "typed", ink = 0, drawing = false, last = null;
          var now = new Date();
          $("dateSigned").value = now.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });

          function updateTyped() { $("typedPreview").textContent = $("typedName").value.trim() || " "; }
          $("typedName").addEventListener("input", updateTyped); updateTyped();

          function setMode(m) {
            mode = m;
            $("tabType").classList.toggle("on", m === "typed"); $("tabDraw").classList.toggle("on", m === "drawn");
            $("typedBox").hidden = m !== "typed"; $("drawBox").hidden = m !== "drawn";
            if (m === "drawn") sizePad();
          }
          $("tabType").addEventListener("click", function () { setMode("typed"); });
          $("tabDraw").addEventListener("click", function () { setMode("drawn"); });

          var pad = $("pad"), ctx = pad.getContext("2d");
          function sizePad() {
            var r = pad.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
            if (!r.width) return;
            var snapshot = ink > 0 ? pad.toDataURL() : null;
            pad.width = Math.round(r.width * dpr); pad.height = Math.round(r.height * dpr);
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
            ctx.lineWidth = 2.4; ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.strokeStyle = "#14305a";
            if (snapshot) { var img = new Image(); img.onload = function () { ctx.drawImage(img, 0, 0, r.width, r.height); }; img.src = snapshot; }
          }
          window.addEventListener("resize", function () { if (mode === "drawn") sizePad(); });
          function pos(e) { var r = pad.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; }
          pad.addEventListener("pointerdown", function (e) {
            e.preventDefault(); drawing = true; last = pos(e);
            try { pad.setPointerCapture(e.pointerId); } catch (x) {}
            ctx.beginPath(); ctx.arc(last.x, last.y, 1.1, 0, Math.PI * 2); ctx.fillStyle = "#14305a"; ctx.fill();
          });
          pad.addEventListener("pointermove", function (e) {
            if (!drawing) return; e.preventDefault();
            var p = pos(e), mid = { x: (last.x + p.x) / 2, y: (last.y + p.y) / 2 };
            ctx.beginPath(); ctx.moveTo(last.x, last.y); ctx.quadraticCurveTo(last.x, last.y, mid.x, mid.y); ctx.lineTo(p.x, p.y); ctx.stroke();
            ink += Math.hypot(p.x - last.x, p.y - last.y); last = p;
            $("padHint").hidden = true;
          });
          function end() { drawing = false; last = null; }
          pad.addEventListener("pointerup", end); pad.addEventListener("pointercancel", end); pad.addEventListener("pointerleave", end);
          $("clearPad").addEventListener("click", function () {
            ctx.clearRect(0, 0, pad.width, pad.height); ink = 0; $("padHint").hidden = false;
          });

          function fail(msg) { $("err").textContent = msg; }
          $("printBlank").addEventListener("click", function () { window.print(); });

          $("accept").addEventListener("click", function () {
            fail("");
            var name = $("typedName").value.trim();
            if (name.length < 2) return fail("Please type your full legal name.");
            if (mode === "drawn" && ink < 40) return fail("Please draw your signature in the box, or choose “Use typed name”.");
            if (!$("consent").checked) return fail("Please agree to sign electronically.");
            if (!$("authority").checked) return fail("Please confirm you are authorized to sign for the business.");
            var signedAt = new Date();
            var label = signedAt.toLocaleString(undefined, { year: "numeric", month: "long", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" });
            var image = mode === "drawn" ? pad.toDataURL("image/png") : null;
            var title = $("title").value.trim();

            var disp = $("sigDisplay"); disp.textContent = "";
            if (image) { var img = document.createElement("img"); img.className = "sigimg"; img.alt = "Signature"; img.src = image; disp.appendChild(img); }
            else { var s = document.createElement("span"); s.className = "script"; s.textContent = name; disp.appendChild(s); }
            $("sigMeta").textContent = name + (title ? ", " + title : "") + " · signed electronically " + label + " · Document ID \(docID)";

            Array.prototype.forEach.call(document.querySelectorAll("#panel input, #panel button"), function (el) { el.disabled = true; });
            $("panel").hidden = true; $("done").hidden = false;
            $("doneText").textContent = "Signed by " + name + " on " + label + ".";

            var payload = { documentId: "\(docID)", typedName: name, title: title, method: mode, image: image,
                            signedAtLabel: label, signedAtISO: signedAt.toISOString(), device: navigator.userAgent };
            if (bridge) {
              $("returnText").textContent = "Saving the signed agreement in Voice Ledger…";
              $("printSigned").hidden = true;
              bridge.postMessage(payload);
            }
            $("clientParty").scrollIntoView({ behavior: "smooth", block: "center" });
          });
          $("printSigned").addEventListener("click", function () { window.print(); });
        })();
        </script>
        """
    }
}
