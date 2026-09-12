#!/usr/bin/env python3
"""Builds the CHOIR voice recording guide as a PDF.

Sentences are read from RECORDING_PROTOCOL.md so the PDF cannot drift from the
script the test suite verifies. No IPA or typographic minus signs: the built-in
ReportLab fonts have no glyphs for them and they render as black boxes.
"""
import re
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (BaseDocTemplate, Frame, PageBreak, PageTemplate,
                                Paragraph, Spacer, Table, TableStyle, KeepTogether)

REPO = "/Users/kianaarabpour/Desktop/Choir"
OUT = "/Users/kianaarabpour/Desktop/Choir/CHOIR_Recording_Guide.pdf"

INK = colors.HexColor("#11171C")
SOFT = colors.HexColor("#3D4A52")
MUTE = colors.HexColor("#66757E")
SIGNAL = colors.HexColor("#0B6E78")
RULE = colors.HexColor("#D3DBDF")
SUNK = colors.HexColor("#F1F4F5")
WARN = colors.HexColor("#9C2F45")
WARNBG = colors.HexColor("#F9ECEE")

styles = getSampleStyleSheet()

# The base-14 fonts are referenced, not embedded, and a viewer without a
# Helvetica substitute renders nothing at all. Embed a real TrueType so the
# file is self-contained wherever it is opened or printed.
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

SUPP = "/System/Library/Fonts/Supplemental"
try:
    pdfmetrics.registerFont(TTFont("Body", f"{SUPP}/Arial.ttf"))
    pdfmetrics.registerFont(TTFont("Body-Bold", f"{SUPP}/Arial Bold.ttf"))
    pdfmetrics.registerFontFamily("Body", normal="Body", bold="Body-Bold")
    REG, BOLD = "Body", "Body-Bold"
except Exception:
    REG, BOLD = "Helvetica", "Helvetica-Bold"


def S(name, **kw):
    base = dict(fontName=REG, fontSize=10, leading=14.5, textColor=INK,
                alignment=TA_LEFT, spaceAfter=0)
    base.update(kw)
    return ParagraphStyle(name, **base)


H1 = S("H1", fontName=BOLD, fontSize=23, leading=26, spaceAfter=4)
SUB = S("SUB", fontSize=11, leading=15, textColor=MUTE, spaceAfter=14)
H2 = S("H2", fontName=BOLD, fontSize=14.5, leading=18,
       textColor=INK, spaceBefore=16, spaceAfter=7)
H3 = S("H3", fontName=BOLD, fontSize=10.5, leading=14,
       textColor=SIGNAL, spaceBefore=10, spaceAfter=4)
BODY = S("BODY", spaceAfter=7)
BULLET = S("BULLET", leftIndent=11, bulletIndent=1, spaceAfter=4)
NOTE = S("NOTE", fontSize=9.5, leading=13.5, textColor=SOFT)
WARNP = S("WARNP", fontSize=9.5, leading=13.5, textColor=WARN)
STEP = S("STEP", fontSize=10, leading=14.5, leftIndent=15, bulletIndent=2,
         spaceAfter=5)
SCRIPT = S("SCRIPT", fontSize=12, leading=19, leftIndent=17, bulletIndent=0,
           spaceAfter=1.5)
SECNOTE = S("SECNOTE", fontSize=9.5, leading=13.5, textColor=MUTE,
            spaceAfter=8)


def read_script():
    """The numbered sentences, grouped by the Part they belong to."""
    text = open(f"{REPO}/RECORDING_PROTOCOL.md", encoding="utf-8").read()
    parts, current = {}, None
    for line in text.split("\n"):
        heading = re.match(r"^## Part ([BCD]) (.*)$", line)
        if heading:
            current = heading.group(1)
            parts[current] = {"title": heading.group(2).strip(" -"), "lines": []}
            continue
        item = re.match(r"^(\d+)\.\s+(.*\S)\s*$", line)
        if item and current and len(item.group(2)) > 12:
            parts[current]["lines"].append((int(item.group(1)), item.group(2)))
    return parts


def box(flowables, bg=SUNK, border=RULE):
    t = Table([[flowables]], colWidths=[165 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("BOX", (0, 0), (-1, -1), 0.6, border),
        ("LEFTPADDING", (0, 0), (-1, -1), 9),
        ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return t


def spec_table(rows, widths=(52, 45, 68)):
    data = [[Paragraph(f'<font name="{BOLD}">{a}</font>', NOTE), Paragraph(b, NOTE), Paragraph(c, NOTE)]
            for a, b, c in rows]
    t = Table(data, colWidths=[w * mm for w in widths])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -2), 0.4, RULE),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont(REG, 7.5)
    canvas.setFillColor(MUTE)
    canvas.drawString(22 * mm, 12 * mm, "CHOIR voice recording guide")
    canvas.drawRightString(188 * mm, 12 * mm, f"{canvas.getPageNumber()}")
    canvas.setStrokeColor(RULE)
    canvas.setLineWidth(0.4)
    canvas.line(22 * mm, 15.5 * mm, 188 * mm, 15.5 * mm)
    canvas.restoreState()


def build():
    parts = read_script()
    doc = BaseDocTemplate(OUT, pagesize=A4,
                          leftMargin=22 * mm, rightMargin=22 * mm,
                          topMargin=20 * mm, bottomMargin=22 * mm,
                          title="CHOIR Voice Recording Guide",
                          author="CHOIR")
    frame = Frame(doc.leftMargin, doc.bottomMargin,
                  doc.width, doc.height, id="body")
    doc.addPageTemplates([PageTemplate(id="all", frames=[frame], onPage=footer)])

    s = []
    B = lambda t, st=BODY: s.append(Paragraph(t, st))
    bullet = lambda t, st=BULLET: s.append(Paragraph(t, st, bulletText="•"))
    gap = lambda h=6: s.append(Spacer(1, h))

    # ---------- cover ----------
    B("Recording your voice for CHOIR", H1)
    B("Everything you need to do, in order. Roughly 90 minutes end to end, "
      "of which about 15 minutes is actual talking.", SUB)

    s.append(box([
        Paragraph("<b>What this produces</b>", NOTE), Spacer(1, 4),
        Paragraph(
            "A recording good enough to train a synthetic voice that sounds "
            "recognisably like you. Your timbre, your accent, your way of "
            "speaking, running entirely on-device with no network.", NOTE),
        Spacer(1, 5),
        Paragraph(
            "Recording quality is the ceiling on the whole project. The models "
            "are commodity now; the data is not. A good microphone in a closet "
            "beats a mediocre one in a studio.", NOTE),
    ]))

    gap(14)
    B("Do this first: the 30-second test", H2)
    B("Do not record all 75 sentences today. Record three, send them, and find "
      "out whether your room and microphone are fighting you. A problem found "
      "in 30 seconds costs 30 seconds. The same problem found after the full "
      "read costs the whole session, because a recording cannot be repeated "
      "under the same conditions.", BODY)

    gap(8)
    B("What you need", H2)
    s.append(spec_table([
        ("Microphone", "USB condenser",
         "The single biggest quality factor. A laptop mic works for the test "
         "but will not make a sellable voice. Never a headset or earbuds: they "
         "compress and denoise, and the model learns the artefacts."),
        ("Room", "Small and soft",
         "A closet with hanging clothes is genuinely better than a large room. "
         "Avoid kitchens and bathrooms. Clothes absorb reflections."),
        ("Quiet", "No fans, no fridge",
         "Turn off air conditioning, close windows, silence your phone and "
         "notifications. A fridge compressor cycling mid-take ruins it."),
        ("Software", "Audacity (free)",
         "QuickTime cannot produce 24-bit WAV. GarageBand fights you on "
         "export. Audacity does exactly what is needed."),
        ("Water", "Room temperature",
         "Not cold, not fizzy. Dry mouth is audible and gets worse over an "
         "hour."),
    ]))

    s.append(PageBreak())

    # ---------- audacity ----------
    B("Setting up Audacity", H2)
    B("These settings matter. Getting them wrong means re-recording.", SECNOTE)

    for n, (t, d) in enumerate([
        ("Open <b>Audio Setup</b> and choose your microphone as the recording device.",
         "Not your built-in mic, if you have plugged something in. Audacity does "
         "not always switch automatically."),
        ("Set <b>Recording Channels</b> to <b>1 (Mono)</b>.",
         "CHOIR is mono end to end. A stereo file from one mic is just the same "
         "signal twice and doubles your file size for nothing."),
        ("Set the <b>Project Rate</b> at the bottom-left to <b>48000 Hz</b>.",
         "This matches CHOIR's audio format exactly, so nothing has to be "
         "resampled before training."),
        ("Set the quality to <b>24-bit</b>.",
         "Audacity &gt; Settings &gt; Quality &gt; Default Sample Format. Gives "
         "headroom for later processing. The engine outputs 16-bit; you record "
         "with room to spare."),
        ("Turn <b>every effect off</b>.",
         "No compression, no noise reduction, no EQ, no de-essing. CHOIR has its "
         "own mastering chain, and processing baked into a recording cannot be "
         "undone. Record flat, even though flat sounds worse on its own."),
    ], 1):
        s.append(Paragraph(f"<b>{n}.</b>&nbsp;&nbsp;{t}", STEP))
        s.append(Paragraph(d, ParagraphStyle("d", parent=NOTE, leftIndent=15,
                                             spaceAfter=8)))

    gap(4)
    B("Setting your level", H3)
    B("Speak a line at the volume you intend to use for the whole session and "
      "watch the recording meter. Aim for the loudest peaks to land around "
      "-6 dB. Then do not touch the gain knob again, in this session or any "
      "later one. Consistent level across every file matters more than perfect "
      "level in any one file.", BODY)

    s.append(box([
        Paragraph("<b>Too quiet is recoverable. Clipping is not.</b>", WARNP),
        Spacer(1, 4),
        Paragraph(
            "If the meter hits the top and turns red, the waveform is squared "
            "off and that information is gone forever. No processing recovers "
            "it. When in doubt, record quieter.", WARNP),
    ], bg=WARNBG, border=WARN))

    gap(14)
    B("How to read", H2)
    B("The way you read is what the model learns. It copies your habits, "
      "including the ones you do not notice.", SECNOTE)

    for t in [
        "<b>Read to one person.</b> Imagine explaining something to a single "
        "attentive friend across a table. Not announcing, not performing, not "
        "reading a bedtime story.",
        "<b>Keep your pace even.</b> Not slow and careful. Your natural "
        "speaking rate, held steady across all 75 lines.",
        "<b>Stay still.</b> Same distance from the mic throughout, about 20 cm, "
        "slightly off to one side so your breath does not hit the capsule "
        "directly. Moving closer and further teaches the model a wobble.",
        "<b>Do not act the punctuation.</b> Read questions as questions and "
        "commands as commands, but naturally. Exaggerated intonation is learned "
        "and reproduced on every sentence afterwards.",
        "<b>Leave the mistakes in the file.</b> Do not stop the recording. Pause "
        "about one second, then say the whole line again from the beginning.",
    ]:
        bullet(t)

    s.append(PageBreak())

    # ---------- the session ----------
    B("The recording session", H2)

    for n, (t, d) in enumerate([
        ("Record 10 seconds of silence.",
         "Press record, sit completely still, say nothing, stop. This is your "
         "room tone. It documents your noise floor and proves the room did not "
         "change between sessions."),
        ("Press record once, and read all 75 lines.",
         "One continuous take. Do not stop and start between sentences. "
         "Splitting one long file is mechanical and I can do it; managing 75 "
         "separate files by hand is miserable and error-prone."),
        ("Pause about one second between sentences.",
         "Sit still and silent during the pause. Those gaps are how the file "
         "gets split automatically, so they need to be genuinely quiet. Do not "
         "shuffle paper or click a mouse in the gap."),
        ("Take a break if you need one.",
         "Stop the recording, rest, then start a second file. Do not push "
         "through fatigue: a tired voice has a different timbre and the model "
         "will learn the tiredness as part of you."),
        ("Export as WAV.",
         "File &gt; Export &gt; Export as WAV, and choose <b>24-bit PCM</b>. "
         "Not MP3, not M4A. Lossy compression destroys exactly the detail the "
         "model needs."),
    ], 1):
        s.append(Paragraph(f"<b>{n}.</b>&nbsp;&nbsp;{t}", STEP))
        s.append(Paragraph(d, ParagraphStyle("d2", parent=NOTE, leftIndent=15,
                                             spaceAfter=8)))

    gap(6)
    B("What to send", H3)
    B("The WAV file, and a note of any line numbers you re-recorded. That is "
      "all. Do not split it, rename it, label it or clean it up. I will cut it "
      "into individual takes, build the manifest the training step needs, and "
      "flag anything clipped, too quiet, or not matching its transcript.", BODY)

    gap(10)
    B("If something goes wrong", H2)
    s.append(spec_table([
        ("Hissy or distant",
         "Gain too low",
         "You are too far from the mic, or the input gain is too low and the "
         "noise floor came up with the signal. Move closer before raising gain."),
        ("Boomy or echoing",
         "Room too live",
         "Hang more soft material, or move into a smaller space. A duvet over "
         "your head and the mic genuinely works."),
        ("Popping on p and b",
         "No pop filter",
         "Angle the mic slightly off-axis from your mouth, or put a sock or "
         "foam shield over it."),
        ("Clicks and mouth noise",
         "Dry mouth",
         "Room-temperature water. Avoid dairy and coffee beforehand."),
        ("Voice changes partway",
         "Fatigue",
         "Stop. Start a fresh file another day and tell me where you stopped."),
    ], widths=(38, 34, 93)))

    s.append(PageBreak())

    # ---------- script ----------
    B("The script", H1)
    B("Read every line, in order. The set is built so that all 40 sounds "
      "CHOIR can produce are exercised; skipping lines leaves gaps the model "
      "cannot fill later.", SUB)

    titles = {
        "B": ("Part B: sound coverage",
              "Each line targets particular sounds. Read naturally; do not "
              "emphasise the words being tested."),
        "C": ("Part C: expression and phrasing",
              "Questions, lists, contrast and pauses. Read these with real but "
              "unexaggerated expression, or the voice will be flat."),
        "D": ("Part D: Scripture and theology",
              "Your subject matter, and the names the engine most needs to say "
              "correctly. Read numbers and references exactly as printed."),
    }

    for key in ("B", "C", "D"):
        if key not in parts:
            continue
        title, note = titles[key]
        block = [Paragraph(title, H2), Paragraph(note, SECNOTE)]
        s.extend(block)
        for num, text in parts[key]["lines"]:
            safe = text.replace("&", "&amp;")
            s.append(Paragraph(f"<font color='#66757E'>{num}.</font>&nbsp;&nbsp;{safe}",
                               SCRIPT))
        gap(6)

    gap(10)
    s.append(box([
        Paragraph("<b>When you are done</b>", NOTE), Spacer(1, 4),
        Paragraph(
            "Send the WAV. The next steps are mine: splitting, training, "
            "converting to Core ML, and measuring the result against CHOIR's "
            "intelligibility gate. The current rule-based voice scores 8.2 "
            "percent word accuracy. That is the number to beat.", NOTE),
    ]))

    doc.build(s)
    print("wrote", OUT)


if __name__ == "__main__":
    build()
