// Builds a Word file from a Markdown doc in docs/ (needs the npm package docx). Usage: node build-docx.js <in.md> <out.docx>
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType,
  BorderStyle, ShadingType, ImageRun, AlignmentType, LevelFormat, Footer, PageNumber,
} = require("docx");

const [, , input, output] = process.argv;
const baseDir = path.dirname(input);
const lines = fs.readFileSync(input, "utf8").split("\n");

const FONT = "Arial";
const MONO = "Consolas";
const TEXT_WIDTH = 11906 - 2 * 1134; // A4, 2 cm margins, DXA
const ACCENT = "2F6FB0";
const BORDER = { style: BorderStyle.SINGLE, size: 4, color: "C9D1DA" };

function runs(text, base = {}) {
  const out = [];
  const re = /(\*\*.+?\*\*|`[^`]+`)/g;
  let last = 0;
  for (const m of text.matchAll(re)) {
    if (m.index > last) out.push(new TextRun({ text: text.slice(last, m.index), ...base }));
    const t = m[0];
    if (t.startsWith("**")) out.push(...runs(t.slice(2, -2), { ...base, bold: true }));
    else out.push(new TextRun({
      text: t.slice(1, -1), font: MONO, size: 18, ...base,
      shading: { type: ShadingType.CLEAR, color: "auto", fill: "F1F3F5" },
    }));
    last = m.index + t.length;
  }
  if (last < text.length) out.push(new TextRun({ text: text.slice(last), ...base }));
  return out;
}

function pngSize(file) {
  const b = fs.readFileSync(file);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20), data: b };
}

const numberingConfigs = [{
  reference: "bullets",
  levels: [0, 1].map((level) => ({
    level, format: LevelFormat.BULLET, text: level === 0 ? "•" : "–", alignment: AlignmentType.LEFT,
    style: { paragraph: { indent: { left: 360 + level * 360, hanging: 280 } } },
  })),
}];
let numberedLists = 0;
let currentNumbered = null;

const children = [];

function table(rows) {
  const cols = rows[0].length;
  // Column widths follow the average text length; a column is never narrower than most of its longest word.
  const weights = Array.from({ length: cols }, (_, c) => {
    const cells = rows.map((r) => (r[c] || "").replace(/[`*]/g, ""));
    const avg = cells.reduce((a, t) => a + t.length, 0) / cells.length;
    const word = Math.max(...cells.flatMap((t) => t.split(/\s+/).map((w) => w.length)));
    return Math.max(Math.min(Math.max(avg, 10), 80), Math.min(word * 0.85, 34));
  });
  const sum = weights.reduce((a, b) => a + b, 0);
  const widths = weights.map((w) => Math.floor((TEXT_WIDTH * w) / sum));
  widths[cols - 1] += TEXT_WIDTH - widths.reduce((a, b) => a + b, 0);
  return new Table({
    width: { size: TEXT_WIDTH, type: WidthType.DXA },
    columnWidths: widths,
    rows: rows.map((r, i) => new TableRow({
      tableHeader: i === 0,
      cantSplit: true,
      children: r.map((cell, c) => new TableCell({
        width: { size: widths[c], type: WidthType.DXA },
        borders: { top: BORDER, bottom: BORDER, left: BORDER, right: BORDER },
        shading: i === 0 ? { type: ShadingType.CLEAR, color: "auto", fill: "EAF2FB" } : undefined,
        margins: { top: 60, bottom: 60, left: 100, right: 100 },
        children: [new Paragraph({ spacing: { after: 0 }, children: runs(cell, { size: 19, bold: i === 0 || undefined }) })],
      })),
    })),
  });
}

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  if (!/^\d+\. /.test(line)) currentNumbered = null;
  if (line.trim() === "") continue;

  let m;
  if ((m = line.match(/^# (.*)/))) {
    children.push(new Paragraph({ heading: HeadingLevel.TITLE, children: [new TextRun(m[1])] }));
  } else if ((m = line.match(/^## (.*)/))) {
    children.push(new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(m[1])] }));
  } else if ((m = line.match(/^### (.*)/))) {
    children.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(m[1])] }));
  } else if ((m = line.match(/^!\[(.*)\]\((.*)\)/))) {
    const img = pngSize(path.join(baseDir, m[2]));
    const width = 640;
    children.push(new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { before: 120, after: 60 }, keepNext: true,
      children: [new ImageRun({ type: "png", data: img.data,
        transformation: { width, height: Math.round((width * img.h) / img.w) },
        altText: { title: m[1], description: m[1], name: path.basename(m[2]) } })],
    }));
    children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 },
      children: [new TextRun({ text: m[1], italics: true, size: 18, color: "52606D" })] }));
  } else if (line.startsWith("|")) {
    const rows = [];
    for (; i < lines.length && lines[i].startsWith("|"); i++) {
      if (/^\|[\s|:-]+\|$/.test(lines[i])) continue;
      rows.push(lines[i].slice(1, -1).split("|").map((s) => s.trim()));
    }
    i--;
    children.push(table(rows));
    children.push(new Paragraph({ spacing: { after: 60 }, children: [] }));
  } else if ((m = line.match(/^( *)- (.*)/))) {
    children.push(new Paragraph({ numbering: { reference: "bullets", level: m[1].length >= 2 ? 1 : 0 },
      spacing: { after: 60 }, children: runs(m[2]) }));
  } else if ((m = line.match(/^\d+\. (.*)/))) {
    if (!currentNumbered) {
      currentNumbered = `num${++numberedLists}`;
      numberingConfigs.push({ reference: currentNumbered, levels: [{ level: 0, format: LevelFormat.DECIMAL,
        text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 360, hanging: 300 } } } }] });
    }
    children.push(new Paragraph({ numbering: { reference: currentNumbered, level: 0 },
      spacing: { after: 60 }, children: runs(m[1]) }));
  } else {
    children.push(new Paragraph({ children: runs(line) }));
  }
}

const doc = new Document({
  creator: "Kirill Saidashev",
  title: (lines.find((l) => l.startsWith("# ")) || "").slice(2),
  styles: {
    default: { document: { run: { font: FONT, size: 21 }, paragraph: { spacing: { after: 120, line: 276 } } } },
    paragraphStyles: [
      { id: "Title", name: "Title", basedOn: "Normal", next: "Normal",
        run: { font: FONT, size: 36, bold: true, color: "1F2933" },
        paragraph: { spacing: { after: 240 }, border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: ACCENT, space: 6 } } } },
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 28, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 360, after: 140 }, keepNext: true, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 24, bold: true, color: "1F2933" },
        paragraph: { spacing: { before: 240, after: 100 }, keepNext: true, outlineLevel: 1 } },
    ],
  },
  numbering: { config: numberingConfigs },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 },
      margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
      children: [new TextRun({ children: [PageNumber.CURRENT], size: 18, color: "7B8794" })] })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => { fs.writeFileSync(output, buf); console.log("written", output); });
