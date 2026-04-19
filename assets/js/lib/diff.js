// Pure diff helpers — no DOM mutation. Ported verbatim from the pre-Phoenix
// app.js so the visual behaviour matches exactly.

export function extractBlocks(container) {
  const blocks = [];
  const children = container.children;
  for (let i = 0; i < children.length; i++) {
    const el = children[i];
    blocks.push({
      tag: el.tagName.toLowerCase(),
      textContent: el.textContent.replace(/\s+/g, " ").trim(),
      outerHTML: el.outerHTML,
    });
  }
  return blocks;
}

export function lcs(a, b, eq) {
  const m = a.length;
  const n = b.length;
  const dp = [];
  for (let i = 0; i <= m; i++) {
    dp[i] = [];
    for (let j = 0; j <= n; j++) {
      if (i === 0 || j === 0) dp[i][j] = 0;
      else if (eq(a[i - 1], b[j - 1])) dp[i][j] = dp[i - 1][j - 1] + 1;
      else dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }

  const result = [];
  let i = m;
  let j = n;
  while (i > 0 && j > 0) {
    if (eq(a[i - 1], b[j - 1])) {
      result.unshift({ ai: i - 1, bi: j - 1 });
      i--;
      j--;
    } else if (dp[i - 1][j] > dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return result;
}

export function computeBlockDiff(oldBlocks, newBlocks) {
  const matched = lcs(
    oldBlocks,
    newBlocks,
    (a, b) => a.tag === b.tag && a.textContent === b.textContent,
  );

  const result = [];
  let oi = 0;
  let ni = 0;
  let mi = 0;

  while (oi < oldBlocks.length || ni < newBlocks.length) {
    if (mi < matched.length && matched[mi].ai === oi && matched[mi].bi === ni) {
      result.push({ type: "unchanged", oldBlock: oldBlocks[oi], newBlock: newBlocks[ni], oldIndex: oi, newIndex: ni });
      oi++;
      ni++;
      mi++;
    } else if (mi < matched.length && oi < matched[mi].ai && ni < matched[mi].bi) {
      const oldEnd = matched[mi].ai;
      const newEnd = matched[mi].bi;
      while (oi < oldEnd && ni < newEnd) {
        if (oldBlocks[oi].tag === newBlocks[ni].tag) {
          result.push({ type: "modified", oldBlock: oldBlocks[oi], newBlock: newBlocks[ni], oldIndex: oi, newIndex: ni });
        } else {
          result.push({ type: "removed", oldBlock: oldBlocks[oi], oldIndex: oi });
          result.push({ type: "added", newBlock: newBlocks[ni], newIndex: ni });
        }
        oi++;
        ni++;
      }
      while (oi < oldEnd) {
        result.push({ type: "removed", oldBlock: oldBlocks[oi], oldIndex: oi });
        oi++;
      }
      while (ni < newEnd) {
        result.push({ type: "added", newBlock: newBlocks[ni], newIndex: ni });
        ni++;
      }
    } else if (oi < oldBlocks.length && (mi >= matched.length || oi < matched[mi].ai)) {
      result.push({ type: "removed", oldBlock: oldBlocks[oi], oldIndex: oi });
      oi++;
    } else if (ni < newBlocks.length) {
      result.push({ type: "added", newBlock: newBlocks[ni], newIndex: ni });
      ni++;
    }
  }

  return result;
}

export function computeWordDiff(oldText, newText) {
  const oldWords = oldText.split(/(\s+)/);
  const newWords = newText.split(/(\s+)/);
  const matched = lcs(oldWords, newWords, (a, b) => a === b);

  const spans = [];
  let oi = 0;
  let ni = 0;
  let mi = 0;

  while (oi < oldWords.length || ni < newWords.length) {
    if (mi < matched.length && matched[mi].ai === oi && matched[mi].bi === ni) {
      spans.push({ type: "same", text: newWords[ni] });
      oi++;
      ni++;
      mi++;
    } else {
      const removedStart = oi;
      while (oi < oldWords.length && (mi >= matched.length || oi < matched[mi].ai)) oi++;
      if (oi > removedStart) {
        spans.push({ type: "removed", text: oldWords.slice(removedStart, oi).join("") });
      }
      const addedStart = ni;
      while (ni < newWords.length && (mi >= matched.length || ni < matched[mi].bi)) ni++;
      if (ni > addedStart) {
        spans.push({ type: "added", text: newWords.slice(addedStart, ni).join("") });
      }
    }
  }

  return spans;
}

function escapeHTML(str) {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export function buildWordDiffHTML(oldText, newText) {
  const spans = computeWordDiff(oldText, newText);
  let html = "";
  for (const span of spans) {
    const escaped = escapeHTML(span.text);
    if (span.type === "same") html += escaped;
    else if (span.type === "added") html += `<span class="inkwell-diff-word-added">${escaped}</span>`;
    else if (span.type === "removed") html += `<span class="inkwell-diff-word-removed">${escaped}</span>`;
  }
  return html;
}

export function createElementFromHTML(htmlString) {
  const temp = document.createElement("div");
  temp.innerHTML = htmlString;
  return temp.firstElementChild;
}
