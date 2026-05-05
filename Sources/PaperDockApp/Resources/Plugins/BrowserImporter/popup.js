const DEFAULT_ENDPOINT = "http://127.0.0.1:23122/mcp/web-import";

const collectionSelect = document.getElementById("collectionSelect");
const newCollectionInput = document.getElementById("newCollection");
const tagSelect = document.getElementById("tagSelect");
const newTagInput = document.getElementById("newTag");
const includePDFInput = document.getElementById("includePDF");
const importButton = document.getElementById("importButton");
const preview = document.getElementById("preview");
const statusNode = document.getElementById("status");
const extensionAPI = globalThis.chrome || globalThis.browser;

const MAX_INLINE_PDF_BYTES = 40 * 1024 * 1024;

let extractedPayload = null;
let litrixEndpoint = DEFAULT_ENDPOINT;

const EDITABLE_PREVIEW_ROWS = [
  { label: "标题", target: "metadata.title" },
  { label: "作者", target: "metadata.authors" },
  { label: "年份", target: "metadata.year" },
  { label: "来源", target: "metadata.source" },
  { label: "DOI", target: "metadata.doi" },
  { label: "摘要", target: "metadata.abstractText", multiline: true },
  { label: "PDF", target: "pdfURL" },
  { label: "网页", target: "pageURL" }
];

function setStatus(message) {
  statusNode.textContent = message || "";
}

function trim(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function extensionCall(api, ...args) {
  return new Promise((resolve, reject) => {
    if (!api) {
      reject(new Error("当前浏览器没有提供扩展 API。"));
      return;
    }
    if (globalThis.browser && !globalThis.chrome) {
      Promise.resolve(api(...args)).then(resolve, reject);
      return;
    }
    api(...args, (result) => {
      const error = extensionAPI.runtime.lastError;
      if (error) {
        reject(new Error(error.message));
      } else {
        resolve(result);
      }
    });
  });
}

async function activeTab() {
  const tabs = await extensionCall(extensionAPI?.tabs?.query?.bind(extensionAPI.tabs), { active: true, currentWindow: true });
  if (!tabs.length || !tabs[0].id) {
    throw new Error("没有找到当前标签页。");
  }
  return tabs[0];
}

async function sendExtractMessage(tabId) {
  return extensionCall(extensionAPI?.tabs?.sendMessage?.bind(extensionAPI.tabs), tabId, { type: "LITRIX_EXTRACT_PAGE" });
}

function isPDFURL(url) {
  return /\.pdf(?:$|[?#])/i.test(url || "") || /\/pdf(?:$|[/?#])/i.test(url || "");
}

function payloadFromPDFTab(tab) {
  const url = tab.url || "";
  if (!isPDFURL(url)) {
    return null;
  }
  const title = (tab.title || url.split("/").pop() || "PDF").replace(/\.pdf$/i, "");
  return {
    ok: true,
    payload: {
      pageURL: url,
      pageTitle: title,
      pdfURL: url,
      pdfURLCandidates: [url],
      metadata: {
        title,
        authors: "",
        year: "",
        source: "",
        doi: "",
        abstractText: "",
        notes: "",
        tags: [],
        collections: [],
        paperType: "电子文献",
        keywords: ""
      }
    }
  };
}

async function extractFromCurrentPage() {
  const tab = await activeTab();
  try {
    return await sendExtractMessage(tab.id);
  } catch {
    if (extensionAPI?.scripting?.executeScript) {
      try {
        await extensionAPI.scripting.executeScript({
          target: { tabId: tab.id },
          files: ["content-script.js"]
        });
        return await sendExtractMessage(tab.id);
      } catch {
        const pdfPayload = payloadFromPDFTab(tab);
        if (pdfPayload) {
          return pdfPayload;
        }
      }
    }

    const pdfPayload = payloadFromPDFTab(tab);
    if (pdfPayload) {
      return pdfPayload;
    }
    throw new Error("浏览器不支持脚本注入，请刷新页面后重试。");
  }
}

function renderPreviewMessage(message) {
  preview.className = "preview empty";
  preview.textContent = message;
}

function renderPreviewPayload(payload) {
  preview.className = "preview";
  preview.replaceChildren();
  EDITABLE_PREVIEW_ROWS.forEach(({ label, target, multiline }) => {
    const row = document.createElement("div");
    row.className = "preview-row";
    const labelNode = document.createElement("div");
    labelNode.className = "preview-label";
    labelNode.textContent = `${label}:`;
    const valueNode = multiline ? document.createElement("textarea") : document.createElement("input");
    valueNode.className = "preview-value";
    if (!multiline) {
      valueNode.type = "text";
    }
    valueNode.dataset.target = target;
    valueNode.value = previewValue(payload, target);
    row.append(labelNode, valueNode);
    preview.append(row);
  });
}

function previewValue(payload, target) {
  const metadata = payload.metadata || {};
  switch (target) {
    case "metadata.title":
      return metadata.title || payload.pageTitle || "";
    case "metadata.authors":
      return metadata.authors || "";
    case "metadata.year":
      return metadata.year || "";
    case "metadata.source":
      return metadata.source || "";
    case "metadata.doi":
      return metadata.doi || "";
    case "metadata.abstractText":
      return metadata.abstractText || "";
    case "pdfURL":
      return payload.pdfURL || "";
    case "pageURL":
      return payload.pageURL || "";
    default:
      return "";
  }
}

function payloadWithPreviewEdits(payload) {
  const nextPayload = JSON.parse(JSON.stringify(payload));
  nextPayload.metadata = nextPayload.metadata || {};
  preview.querySelectorAll("[data-target]").forEach((node) => {
    const value = trimMultiline(node.value || "");
    switch (node.dataset.target) {
      case "metadata.title":
        nextPayload.metadata.title = value;
        nextPayload.pageTitle = value || nextPayload.pageTitle || "";
        break;
      case "metadata.authors":
        nextPayload.metadata.authors = value;
        break;
      case "metadata.year":
        nextPayload.metadata.year = value;
        break;
      case "metadata.source":
        nextPayload.metadata.source = value;
        break;
      case "metadata.doi":
        nextPayload.metadata.doi = value;
        break;
      case "metadata.abstractText":
        nextPayload.metadata.abstractText = value;
        break;
      case "pdfURL":
        nextPayload.pdfURL = value;
        break;
      case "pageURL":
        nextPayload.pageURL = value;
        break;
      default:
        break;
    }
  });
  return nextPayload;
}

function trimMultiline(value) {
  return String(value || "").replace(/\r\n/g, "\n").trim();
}

async function loadSettings() {
  const stored = await extensionCall(extensionAPI?.storage?.sync?.get?.bind(extensionAPI.storage.sync), {
    litrixEndpoint: DEFAULT_ENDPOINT
  });
  litrixEndpoint = trim(stored.litrixEndpoint) || DEFAULT_ENDPOINT;
}

async function saveEndpoint() {
  await extensionCall(extensionAPI?.storage?.sync?.set?.bind(extensionAPI.storage.sync), { litrixEndpoint });
}

function contextURLForEndpoint(endpoint) {
  const url = new URL(endpoint);
  url.pathname = url.pathname.replace(/\/$/, "") + "/context";
  url.search = "";
  url.hash = "";
  return url.href;
}

function setSelectOptions(select, defaultLabel, values) {
  const currentValue = select.value;
  select.replaceChildren();
  const emptyOption = document.createElement("option");
  emptyOption.value = "";
  emptyOption.textContent = defaultLabel;
  select.append(emptyOption);

  values.forEach((value) => {
    const name = trim(typeof value === "string" ? value : value?.name);
    if (!name) {
      return;
    }
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    if (typeof value === "object" && value.color) {
      option.style.color = value.color;
    }
    select.append(option);
  });

  if (currentValue && Array.from(select.options).some((option) => option.value === currentValue)) {
    select.value = currentValue;
  }
}

async function loadImportContext() {
  try {
    const response = await fetch(contextURLForEndpoint(litrixEndpoint), {
      method: "GET",
      headers: {
        "X-Litrix-Source": "browser-extension"
      }
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const context = await response.json();
    setSelectOptions(collectionSelect, "无分类", Array.isArray(context.collections) ? context.collections : []);
    setSelectOptions(tagSelect, "无标签", Array.isArray(context.tags) ? context.tags : []);
  } catch {
    setSelectOptions(collectionSelect, "无分类", []);
    setSelectOptions(tagSelect, "无标签", []);
  }
}

function uniqueValues(values) {
  const seen = new Set();
  const result = [];
  values.flatMap(splitListInput).map(trim).filter(Boolean).forEach((value) => {
    const key = value.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      result.push(value);
    }
  });
  return result;
}

function splitListInput(value) {
  return String(value || "")
    .split(/[；;]+/g)
    .map(trim)
    .filter(Boolean);
}

function selectedCollections() {
  return uniqueValues([collectionSelect.value, newCollectionInput.value]);
}

function selectedTags() {
  return uniqueValues([tagSelect.value, newTagInput.value]);
}

function payloadWithUserChoices(payload) {
  const nextPayload = payloadWithPreviewEdits(payload);
  nextPayload.metadata = nextPayload.metadata || {};
  nextPayload.metadata.collections = selectedCollections();
  nextPayload.metadata.tags = selectedTags();
  nextPayload.metadata.notes = trim(nextPayload.metadata.notes);
  return nextPayload;
}

function uniqueURLs(values) {
  const seen = new Set();
  const result = [];
  values.filter(Boolean).forEach((value) => {
    try {
      const url = new URL(value).href;
      if (!seen.has(url)) {
        seen.add(url);
        result.push(url);
      }
    } catch {
      // Ignore malformed candidates from publisher markup.
    }
  });
  return result;
}

function pdfMagic(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer.slice(0, 5));
  return bytes.length >= 5 &&
    bytes[0] === 0x25 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x44 &&
    bytes[3] === 0x46 &&
    bytes[4] === 0x2d;
}

function arrayBufferToBase64(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  const chunkSize = 0x8000;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

function fileNameFromDisposition(value) {
  const text = value || "";
  const utf8Match = text.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
  if (utf8Match) {
    try {
      return decodeURIComponent(utf8Match[1].replace(/"/g, ""));
    } catch {
      return utf8Match[1].replace(/"/g, "");
    }
  }
  const plainMatch = text.match(/filename\s*=\s*"?([^";]+)"?/i);
  return plainMatch ? plainMatch[1] : "";
}

function fileNameFromURL(url) {
  try {
    const parsed = new URL(url);
    const last = parsed.pathname.split("/").filter(Boolean).pop() || "";
    return last || "Litrix-Web.pdf";
  } catch {
    return "Litrix-Web.pdf";
  }
}

async function fetchPDFCandidate(url) {
  const response = await fetch(url, {
    method: "GET",
    credentials: "include",
    redirect: "follow",
    cache: "no-store"
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const contentLength = Number(response.headers.get("content-length") || "0");
  if (contentLength > MAX_INLINE_PDF_BYTES) {
    throw new Error("PDF 超过浏览器直接传输上限。");
  }

  const arrayBuffer = await response.arrayBuffer();
  if (arrayBuffer.byteLength > MAX_INLINE_PDF_BYTES) {
    throw new Error("PDF 超过浏览器直接传输上限。");
  }

  const contentType = response.headers.get("content-type") || "";
  const finalURL = response.url || url;
  const looksLikePDF = /pdf/i.test(contentType) || isPDFURL(finalURL) || pdfMagic(arrayBuffer);
  if (!looksLikePDF) {
    throw new Error("下载结果不是 PDF。");
  }

  return {
    pdfURL: finalURL,
    pdfDataBase64: arrayBufferToBase64(arrayBuffer),
    pdfFileName: fileNameFromDisposition(response.headers.get("content-disposition")) || fileNameFromURL(finalURL),
    pdfContentType: contentType || "application/pdf",
    pdfByteLength: arrayBuffer.byteLength
  };
}

async function attachInlinePDFIfPossible(payload) {
  const candidates = uniqueURLs([
    payload.pdfURL,
    ...(Array.isArray(payload.pdfURLCandidates) ? payload.pdfURLCandidates : [])
  ]);
  if (!candidates.length) {
    return { payload, status: "未发现 PDF 链接。" };
  }

  const nextPayload = JSON.parse(JSON.stringify(payload));
  let lastError = null;
  for (const url of candidates.slice(0, 4)) {
    try {
      setStatus("正在用浏览器下载 PDF...");
      const pdf = await fetchPDFCandidate(url);
      nextPayload.pdfURL = pdf.pdfURL;
      nextPayload.pdfDataBase64 = pdf.pdfDataBase64;
      nextPayload.pdfFileName = pdf.pdfFileName;
      nextPayload.pdfContentType = pdf.pdfContentType;
      nextPayload.pdfByteLength = pdf.pdfByteLength;
      return { payload: nextPayload, status: "PDF 已由浏览器下载，将随条目导入。" };
    } catch (error) {
      lastError = error;
    }
  }

  nextPayload.pdfURL = candidates[0];
  return {
    payload: nextPayload,
    status: `浏览器未能直接下载 PDF，已发送链接给 Litrix 尝试下载。${lastError ? `（${lastError.message}）` : ""}`
  };
}

async function readCurrentPage() {
  importButton.disabled = true;
  setStatus("正在读取当前网页...");
  try {
    const response = await extractFromCurrentPage();
    if (!response?.ok || !response.payload) {
      throw new Error("没有读取到网页信息。");
    }
    extractedPayload = response.payload;
    renderPreviewPayload(extractedPayload);
    importButton.disabled = false;
    setStatus("网页信息已读取。");
  } catch (error) {
    extractedPayload = null;
    renderPreviewMessage(error.message);
    setStatus("读取失败。");
  }
}

importButton.addEventListener("click", async () => {
  if (!extractedPayload) {
    return;
  }
  importButton.disabled = true;
  setStatus("正在发送到 Litrix...");
  try {
    await saveEndpoint();
    let payload = payloadWithUserChoices(extractedPayload);
    if (includePDFInput.checked) {
      const inlineResult = await attachInlinePDFIfPossible(payload);
      payload = inlineResult.payload;
      setStatus(inlineResult.status);
    } else {
      payload.pdfURL = "";
      payload.pdfURLCandidates = [];
    }

    const response = await fetch(litrixEndpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Litrix-Source": "browser-extension"
      },
      body: JSON.stringify(payload)
    });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(text || `HTTP ${response.status}`);
    }
    const result = JSON.parse(text);
    setStatus(result.duplicate ? "Litrix 已有相同条目。" : "已创建 Litrix 条目。");
    renderPreviewPayload(payload);
    await loadImportContext();
  } catch (error) {
    setStatus(`导入失败：${error.message}`);
  } finally {
    importButton.disabled = false;
  }
});

loadSettings()
  .then(loadImportContext)
  .then(readCurrentPage)
  .catch((error) => setStatus(error.message));
