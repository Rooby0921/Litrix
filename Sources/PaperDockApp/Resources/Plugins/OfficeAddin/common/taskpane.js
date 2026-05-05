const endpointInput = document.getElementById("endpoint");
const styleSelect = document.getElementById("style");
const typeSelect = document.getElementById("type");
const queryInput = document.getElementById("query");
const searchButton = document.getElementById("searchButton");
const insertButton = document.getElementById("insertButton");
const copyButton = document.getElementById("copyButton");
const resultsNode = document.getElementById("results");
const statusNode = document.getElementById("status");

let selectedItem = null;

function setStatus(message) {
  statusNode.textContent = message || "";
}

function clean(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function splitAuthors(authors) {
  return clean(authors)
    .split(/;|；|\band\b|，/)
    .map(clean)
    .filter(Boolean);
}

function authorLead(item) {
  const authors = splitAuthors(item.authors);
  if (!authors.length) {
    return "Unknown";
  }
  const first = authors[0];
  const parts = first.split(/\s+/).filter(Boolean);
  return parts.length > 1 ? parts[parts.length - 1] : first;
}

function doiPart(item) {
  return clean(item.doi) ? ` https://doi.org/${clean(item.doi).replace(/^https?:\/\/doi\.org\//i, "")}` : "";
}

function fullCitation(item) {
  const author = clean(item.authors) || "Unknown author";
  const year = clean(item.year) || "n.d.";
  const title = clean(item.title) || "Untitled";
  const source = clean(item.source);
  const sourcePart = source ? ` ${source}.` : "";
  return `${author}. ${title}. ${sourcePart} ${year}.${doiPart(item)}`.replace(/\s+/g, " ").trim();
}

function formattedCitation(item) {
  const lead = authorLead(item);
  const year = clean(item.year) || "n.d.";
  const title = clean(item.title) || "Untitled";
  const type = typeSelect.value;
  const style = styleSelect.value;

  if (type === "footnote" || type === "endnote") {
    return fullCitation(item);
  }

  switch (style) {
    case "gbt7714":
      return `[${lead}, ${year}]`;
    case "mla9":
      return `(${lead})`;
    case "chicago":
      return `(${lead} ${year})`;
    case "apa7":
    default:
      return `(${lead}, ${year})`;
  }
}

async function callLitrixTool(name, args) {
  const response = await fetch(endpointInput.value.trim(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: Date.now(),
      method: "tools/call",
      params: {
        name,
        arguments: args
      }
    })
  });
  const json = await response.json();
  if (!response.ok || json.error) {
    throw new Error(json.error?.message || `HTTP ${response.status}`);
  }
  const result = json.result || {};
  if (result.isError) {
    throw new Error(result.content?.[0]?.text || "Litrix tool call failed.");
  }
  return result.structuredContent || {};
}

function renderResults(items) {
  resultsNode.innerHTML = "";
  selectedItem = null;
  insertButton.disabled = true;
  copyButton.disabled = true;

  if (!items.length) {
    resultsNode.textContent = "没有结果。";
    return;
  }

  items.forEach((item, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "result";
    button.innerHTML = `
      <div class="title"></div>
      <div class="meta"></div>
    `;
    button.querySelector(".title").textContent = clean(item.title) || "Untitled";
    button.querySelector(".meta").textContent = [
      clean(item.authors),
      clean(item.year),
      clean(item.source)
    ].filter(Boolean).join(" · ");
    button.addEventListener("click", () => {
      selectedItem = item;
      Array.from(resultsNode.querySelectorAll(".result")).forEach((node) => {
        node.classList.remove("selected");
      });
      button.classList.add("selected");
      insertButton.disabled = false;
      copyButton.disabled = false;
      setStatus(`已选择：${clean(item.title) || "Untitled"}`);
    });
    resultsNode.appendChild(button);
    if (index === 0) {
      button.click();
    }
  });
}

async function search() {
  const query = clean(queryInput.value);
  if (!query) {
    setStatus("请输入搜索词。");
    return;
  }

  searchButton.disabled = true;
  setStatus("正在搜索 Litrix...");
  try {
    const result = await callLitrixTool("search_library", { query, limit: 8 });
    renderResults(result.items || []);
    setStatus(`返回 ${result.returnedCount || 0} 条结果。`);
  } catch (error) {
    setStatus(`搜索失败：${error.message}`);
  } finally {
    searchButton.disabled = false;
  }
}

async function insertTextIntoDocument(text) {
  if (!window.Word || !window.Office) {
    await navigator.clipboard.writeText(text);
    setStatus("当前宿主不支持 Office.js 插入，引用已复制到剪贴板。");
    return;
  }

  await Word.run(async (context) => {
    const range = context.document.getSelection();
    const type = typeSelect.value;
    try {
      if (type === "footnote" && typeof range.insertFootnote === "function") {
        range.insertFootnote(text);
      } else if (type === "endnote" && typeof range.insertEndnote === "function") {
        range.insertEndnote(text);
      } else {
        range.insertText(text, Word.InsertLocation.after);
      }
      await context.sync();
    } catch {
      range.insertText(text, Word.InsertLocation.after);
      await context.sync();
    }
  });
}

searchButton.addEventListener("click", search);
queryInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    search();
  }
});

insertButton.addEventListener("click", async () => {
  if (!selectedItem) {
    return;
  }
  const citation = formattedCitation(selectedItem);
  insertButton.disabled = true;
  try {
    await insertTextIntoDocument(citation);
    setStatus("引用已插入。");
  } catch (error) {
    setStatus(`插入失败：${error.message}`);
  } finally {
    insertButton.disabled = false;
  }
});

copyButton.addEventListener("click", async () => {
  if (!selectedItem) {
    return;
  }
  await navigator.clipboard.writeText(formattedCitation(selectedItem));
  setStatus("引用已复制。");
});

if (window.Office) {
  Office.onReady(() => setStatus("Litrix 引用插件已就绪。"));
} else {
  setStatus("离线预览模式：可搜索和复制引用。");
}
