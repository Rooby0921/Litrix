(() => {
  if (window.__litrixWebImporterInstalled) {
    return;
  }
  window.__litrixWebImporterInstalled = true;

  const listSeparators = /[;,，；]\s*/;
  const doiPattern = /10\.\d{4,9}\/[-._;()/:A-Z0-9]+/i;

  function trim(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
  }

  function firstNonEmpty(...values) {
    return values.map(trim).find(Boolean) || "";
  }

  function allMetaValues(keys) {
    const wanted = new Set(keys.map((key) => key.toLowerCase()));
    return Array.from(document.querySelectorAll("meta"))
      .filter((meta) => {
        const name = trim(
          meta.getAttribute("name") ||
          meta.getAttribute("property") ||
          meta.getAttribute("itemprop")
        ).toLowerCase();
        return wanted.has(name);
      })
      .map((meta) => trim(meta.getAttribute("content")))
      .filter(Boolean);
  }

  function firstMeta(keys) {
    return allMetaValues(keys)[0] || "";
  }

  function absoluteURL(value) {
    const trimmed = trim(value);
    if (!trimmed || /^javascript:/i.test(trimmed)) {
      return "";
    }
    try {
      return new URL(trimmed, window.location.href).href;
    } catch {
      return "";
    }
  }

  function unique(values) {
    const seen = new Set();
    const result = [];
    values.map(trim).filter(Boolean).forEach((value) => {
      const key = value.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        result.push(value);
      }
    });
    return result;
  }

  function extractYear(value) {
    const match = trim(value).match(/\b(18|19|20|21)\d{2}\b/);
    return match ? match[0] : "";
  }

  function splitList(value) {
    return trim(value).split(listSeparators).map(trim).filter(Boolean);
  }

  function cleanAuthorName(value) {
    let author = trim(value)
      .replace(/\([^)]*(?:University|Department|College|School|Institute|Email|ORCID|Corresponding)[^)]*\)/gi, " ")
      .replace(/(\p{L})[0-9*†‡§]+/gu, "$1")
      .replace(/^[0-9*†‡§]+\s*/g, "")
      .replace(/\s*&\s*….*$/u, "")
      .replace(/…/g, " ")
      .replace(/\b(?:Show authors|Authors and Affiliations|View author publications|Search author on)\b.*$/gi, " ");
    author = trim(author);
    return author.replace(/^[,;:|\/\\()[\]{}<>*\s]+|[,;:|\/\\()[\]{}<>*\s]+$/g, "");
  }

  function isLikelyAuthorName(value) {
    const author = trim(value);
    const lowered = author.toLowerCase();
    if (author.length < 2 || author.length > 120) {
      return false;
    }
    if (/\b(18|19|20|21)\d{2}\b/.test(author)) {
      return false;
    }
    return !/abstract|keyword|university|department|journal|conference|doi|copyright|received|accepted|available online|authors and affiliations|view author|search author|@|https?:\/\//i.test(lowered);
  }

  function authorKey(value) {
    return trim(value)
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^\p{L}\p{N}]+/gu, "");
  }

  function uniqueAuthors(values) {
    const seen = new Set();
    const result = [];
    values.map(cleanAuthorName).filter(isLikelyAuthorName).forEach((value) => {
      const key = authorKey(value);
      if (key && !seen.has(key)) {
        seen.add(key);
        result.push(value);
      }
    });
    return result;
  }

  function cleanDOI(value) {
    const match = trim(value).match(doiPattern);
    return match ? match[0].replace(/[.,;)\]\s]+$/, "") : "";
  }

  function decodeEntities(value) {
    const textarea = document.createElement("textarea");
    textarea.innerHTML = value || "";
    return textarea.value;
  }

  function flattenJSONLD(value, output = []) {
    if (Array.isArray(value)) {
      value.forEach((item) => flattenJSONLD(item, output));
      return output;
    }
    if (!value || typeof value !== "object") {
      return output;
    }
    output.push(value);
    if (value["@graph"]) {
      flattenJSONLD(value["@graph"], output);
    }
    return output;
  }

  function jsonLDNodes() {
    const nodes = [];
    Array.from(document.querySelectorAll("script[type*='ld+json']")).forEach((script) => {
      try {
        flattenJSONLD(JSON.parse(script.textContent || ""), nodes);
      } catch {
        // Publishers often emit slightly invalid JSON-LD. Meta tags still cover those pages.
      }
    });
    return nodes;
  }

  function schemaTypes(node) {
    const raw = node?.["@type"];
    return (Array.isArray(raw) ? raw : [raw]).map((value) => trim(value).toLowerCase());
  }

  function isPaperLikeNode(node) {
    const types = schemaTypes(node);
    return types.some((type) =>
      ["scholarlyarticle", "article", "report", "chapter", "creativework"].includes(type)
    );
  }

  function preferredJSONLDNode(nodes) {
    return nodes.find((node) => schemaTypes(node).includes("scholarlyarticle")) ||
      nodes.find(isPaperLikeNode) ||
      nodes[0] ||
      {};
  }

  function jsonText(value) {
    if (value == null) {
      return "";
    }
    if (typeof value === "string" || typeof value === "number") {
      return trim(value);
    }
    if (Array.isArray(value)) {
      return value.map(jsonText).filter(Boolean).join("; ");
    }
    if (typeof value === "object") {
      return firstNonEmpty(
        value.name,
        value.headline,
        value.alternateName,
        value.text,
        value.value,
        value.identifier,
        value.url,
        value["@id"]
      );
    }
    return "";
  }

  function jsonAuthors(node) {
    const raw = node.author || node.creator || node.contributor || [];
    const values = Array.isArray(raw) ? raw : [raw];
    return values.map((item) => {
      if (typeof item === "string") {
        return item;
      }
      const given = trim(item?.givenName);
      const family = trim(item?.familyName);
      return firstNonEmpty(item?.name, [given, family].filter(Boolean).join(" "), item?.["@id"]);
    }).filter(Boolean);
  }

  function jsonKeywords(node) {
    const raw = node.keywords || node.about || node.genre || "";
    if (Array.isArray(raw)) {
      return raw.flatMap((item) => splitList(jsonText(item)));
    }
    return splitList(jsonText(raw));
  }

  function jsonSource(node) {
    const part = node.isPartOf || node.publisher || node.sourceOrganization;
    if (Array.isArray(part)) {
      return jsonText(part[0]);
    }
    return jsonText(part);
  }

  function extractDOI(jsonNode) {
    const direct = firstMeta([
      "citation_doi",
      "dc.identifier",
      "dc.identifier.doi",
      "dcterms.identifier",
      "prism.doi"
    ]);
    const fromDirect = cleanDOI(direct);
    if (fromDirect) {
      return fromDirect;
    }

    const jsonValues = [
      jsonText(jsonNode.identifier),
      jsonText(jsonNode.sameAs),
      jsonText(jsonNode.url)
    ];
    for (const value of jsonValues) {
      const doi = cleanDOI(value);
      if (doi) {
        return doi;
      }
    }

    const fromPage = document.body?.innerText?.match(doiPattern);
    return fromPage ? fromPage[0].replace(/[.,;)\]\s]+$/, "") : "";
  }

  function pageRange(first, last, fallback) {
    const start = trim(first);
    const end = trim(last);
    if (start && end && start !== end) {
      return `${start}-${end}`;
    }
    return start || end || trim(fallback);
  }

  function cleanSource(value, year) {
    let source = trim(value);
    if (!source) {
      return "";
    }
    const escapedYear = trim(year).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (escapedYear) {
      source = source.replace(new RegExp(`\\s+${escapedYear}\\s+\\d+[A-Za-z]?\\s*:\\s*\\d+[A-Za-z]?\\s*$`, "i"), "");
      source = source.replace(new RegExp(`\\s+\\d+[A-Za-z]?\\s*,\\s*\\d+[A-Za-z]?\\s*\\(\\s*${escapedYear}\\s*\\)\\s*$`, "i"), "");
    }
    source = source
      .replace(/\s+\bvol(?:ume)?\.?\s*\d.*$/i, "")
      .replace(/\s+\bno\.?\s*\d.*$/i, "")
      .replace(/\s+\bissue\s*\d.*$/i, "")
      .replace(/\s*,?\s*(?:pp?\.?|pages?)\s*\d+.*$/i, "");
    return trim(source.replace(/^[,.;:|]+|[,.;:|]+$/g, ""));
  }

  function pdfURLScore(url, label = "", type = "", source = "") {
    const joined = `${url} ${label} ${type} ${source}`.toLowerCase();
    let score = 0;
    if (/citation_pdf_url|schema/.test(source)) score += 50;
    if (/application\/pdf|pdf/.test(type)) score += 35;
    if (/\.pdf(?:$|[?#])/.test(url.toLowerCase())) score += 35;
    if (/(^|[/?&=_-])pdf($|[/?&=_-])|downloadpdf|articlepdf|pdfdownload|fulltextpdf/.test(joined)) score += 24;
    if (/full\s*text|full-text|download|下载|全文|pdf/.test(joined)) score += 12;
    if (/supplement|appendix|cover|thumbnail|preview|figure|image|slides/.test(joined)) score -= 25;
    return score;
  }

  function addPDFCandidate(candidates, value, source, label = "", type = "") {
    const url = absoluteURL(value);
    if (!url) {
      return;
    }
    const score = pdfURLScore(url, label, type, source);
    if (score <= 0) {
      return;
    }
    candidates.push({ url, score, source });
  }

  function addPDFCandidatesFromJSON(value, candidates, source) {
    if (!value) {
      return;
    }
    if (typeof value === "string") {
      addPDFCandidate(candidates, value, source, value, "");
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((item) => addPDFCandidatesFromJSON(item, candidates, source));
      return;
    }
    if (typeof value === "object") {
      addPDFCandidate(candidates, value.contentUrl || value.url || value["@id"], source, jsonText(value), value.encodingFormat || value.fileFormat || "");
      ["encoding", "associatedMedia", "hasPart", "mainEntityOfPage", "sameAs"].forEach((key) => {
        addPDFCandidatesFromJSON(value[key], candidates, source);
      });
    }
  }

  function extractPDFURLCandidates(jsonNode) {
    const candidates = [];

    if (/\.pdf(?:$|[?#])/i.test(window.location.href) || /application\/pdf/i.test(document.contentType || "")) {
      addPDFCandidate(candidates, window.location.href, "current_url", "current PDF", "application/pdf");
    }

    allMetaValues(["citation_pdf_url"]).forEach((value) => {
      addPDFCandidate(candidates, value, "citation_pdf_url", "citation_pdf_url", "application/pdf");
    });

    addPDFCandidatesFromJSON(jsonNode, candidates, "schema");

    Array.from(document.querySelectorAll("a[href], area[href], link[href]")).forEach((link) => {
      const href = link.getAttribute("href");
      const label = trim([
        link.textContent,
        link.getAttribute("title"),
        link.getAttribute("aria-label"),
        link.getAttribute("download"),
        link.getAttribute("rel")
      ].filter(Boolean).join(" "));
      const type = trim(link.getAttribute("type"));
      addPDFCandidate(candidates, href, "link", label, type);
    });

    Array.from(document.querySelectorAll("[data-pdf-url], [data-pdf], [data-download-url], [data-url], [data-href]"))
      .forEach((node) => {
        ["data-pdf-url", "data-pdf", "data-download-url", "data-url", "data-href"].forEach((name) => {
          addPDFCandidate(candidates, node.getAttribute(name), "data_attribute", node.textContent, "");
        });
      });

    Array.from(document.querySelectorAll("[onclick]")).slice(0, 80).forEach((node) => {
      const onclick = node.getAttribute("onclick") || "";
      const match = onclick.match(/['"]([^'"]*(?:\.pdf|\/pdf|downloadpdf|articlepdf)[^'"]*)['"]/i);
      if (match) {
        addPDFCandidate(candidates, decodeEntities(match[1]), "onclick", node.textContent, "");
      }
    });

    const bestByURL = new Map();
    candidates.forEach((candidate) => {
      const previous = bestByURL.get(candidate.url);
      if (!previous || candidate.score > previous.score) {
        bestByURL.set(candidate.url, candidate);
      }
    });

    return Array.from(bestByURL.values())
      .sort((left, right) => right.score - left.score)
      .map((candidate) => candidate.url);
  }

  function extractLitrixPayload() {
    const jsonNodes = jsonLDNodes();
    const jsonNode = preferredJSONLDNode(jsonNodes);

    const title = firstNonEmpty(
      firstMeta([
        "citation_title",
        "dc.title",
        "dcterms.title",
        "og:title",
        "twitter:title"
      ]),
      jsonText(jsonNode.headline || jsonNode.name),
      document.title
    );

    const citationAuthors = uniqueAuthors(allMetaValues(["citation_author"]));
    const structuredAuthors = citationAuthors.length > 0
      ? citationAuthors
      : uniqueAuthors([
        ...allMetaValues(["dc.creator", "dcterms.creator", "author"]),
        ...jsonAuthors(jsonNode)
      ]);
    const fallbackAuthors = structuredAuthors.length > 0
      ? []
      : uniqueAuthors(
        Array.from(document.querySelectorAll("[rel='author'], .author, .authors, [class*='author']"))
          .slice(0, 8)
          .map((node) => node.textContent)
      );
    const authors = uniqueAuthors([...structuredAuthors, ...fallbackAuthors]);

    const date = firstNonEmpty(
      firstMeta([
        "citation_publication_date",
        "citation_online_date",
        "citation_date",
        "dc.date",
        "dcterms.issued",
        "article:published_time",
        "prism.publicationdate"
      ]),
      jsonText(jsonNode.datePublished || jsonNode.dateCreated || jsonNode.dateModified)
    );

    const source = firstNonEmpty(
      cleanSource(firstMeta(["citation_journal_title"]), extractYear(date)),
      cleanSource(firstMeta(["citation_conference_title"]), extractYear(date)),
      cleanSource(firstMeta(["prism.publicationname"]), extractYear(date)),
      cleanSource(firstMeta(["dc.source"]), extractYear(date)),
      cleanSource(firstMeta(["dcterms.source"]), extractYear(date)),
      cleanSource(jsonSource(jsonNode), extractYear(date)),
      cleanSource(firstMeta(["og:site_name"]), extractYear(date)),
      cleanSource(firstMeta(["citation_publisher"]), extractYear(date))
    );

    const keywords = unique([
      ...allMetaValues(["citation_keywords", "keywords", "dc.subject", "dcterms.subject"])
        .flatMap(splitList),
      ...jsonKeywords(jsonNode)
    ]);

    const abstractText = firstNonEmpty(
      firstMeta([
        "citation_abstract",
        "dc.description",
        "dcterms.abstract",
        "description",
        "og:description"
      ]),
      jsonText(jsonNode.abstract || jsonNode.description)
    );

    const pdfURLCandidates = extractPDFURLCandidates(jsonNode);
    const pageURL = window.location.href;
    const firstPage = firstMeta(["citation_firstpage", "prism.startingpage"]);
    const lastPage = firstMeta(["citation_lastpage", "prism.endingpage"]);

    return {
      pageURL,
      pageTitle: trim(document.title),
      pdfURL: pdfURLCandidates[0] || "",
      pdfURLCandidates,
      metadata: {
        title,
        authors: authors.join("; "),
        year: extractYear(date),
        source,
        doi: extractDOI(jsonNode),
        abstractText,
        notes: "",
        tags: [],
        collections: [],
        paperType: "电子文献",
        volume: firstMeta(["citation_volume", "prism.volume"]),
        issue: firstMeta(["citation_issue", "prism.number"]),
        pages: pageRange(firstPage, lastPage, jsonText(jsonNode.pagination || jsonNode.pageStart)),
        keywords: keywords.join("; ")
      }
    };
  }

  const runtime = globalThis.chrome?.runtime || globalThis.browser?.runtime;
  runtime?.onMessage?.addListener((message, _sender, sendResponse) => {
    if (message?.type !== "LITRIX_EXTRACT_PAGE") {
      return false;
    }
    sendResponse({
      ok: true,
      payload: extractLitrixPayload()
    });
    return true;
  });
})();
