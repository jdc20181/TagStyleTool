import { apiInitializer } from "discourse/lib/api";
import { iconHTML } from "discourse/lib/icon-library";
import { defaultRenderTag } from "discourse/lib/render-tag";

function normalizeIconName(iconName) {
  if (!iconName || typeof iconName !== "string") {
    return "";
  }

  let newName = iconName.trim();

  return newName;
}

function hexToRgb(hex) {
  if (typeof hex !== "string") {
    return null;
  }

  let value = hex.trim().replace(/^#/, "");
  if (value.length === 3) {
    value = value
      .split("")
      .map((char) => char + char)
      .join("");
  }

  if (!/^[0-9a-fA-F]{6}$/.test(value)) {
    return null;
  }

  const num = parseInt(value, 16);
  return [(num >> 16) & 255, (num >> 8) & 255, num & 255];
}

function luminance(rgb) {
  const c = [rgb[0], rgb[1], rgb[2]].map((v) => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function contrastColor(hexColor) {
  const rgb = hexToRgb(hexColor);
  if (!rgb) {
    return "";
  }
  return luminance(rgb) >= 0.45 ? "#000d" : "#fffd";
}

function parseTagIconList(rawList) {
  const map = {};
  if (!rawList || typeof rawList !== "string") {
    return map;
  }

  rawList.split("|").forEach((line) => {
    const parts = line.split(",");
    if (parts.length < 2) {
      return;
    }

    const tagName = (parts[0] || "").trim().toLowerCase();
    const iconName = (parts[1] || "").trim();
    const color = (parts[2] || "").trim();

    if (tagName && iconName) {
      map[tagName] = { icon: normalizeIconName(iconName), color };
    }
  });

  return map;
}

function replaceDashesInTextNodes(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
  let node = walker.nextNode();
  while (node) {
    node.nodeValue = node.nodeValue.replace(/-/g, " ");
    node = walker.nextNode();
  }
}

export default apiInitializer((api) => {
  const tagMap = parseTagIconList(settings.tag_icon_list || "");
  const enableColors = !!settings.enable_colors_for_tag_labels;

  if (api.registerCustomTagSectionLinkPrefixIcon) {
    Object.entries(tagMap).forEach(([tagName, tagOptions]) => {
      api.registerCustomTagSectionLinkPrefixIcon({
        tagName,
        prefixValue: tagOptions.icon,
        prefixColor: tagOptions.color || undefined,
      });
    });
  }

  api.replaceTagRenderer((tag, params) => {
    const rendered = defaultRenderTag(tag, params);
    if (!rendered || typeof rendered !== "string") {
      return rendered;
    }

    const parser = new DOMParser();
    const doc = parser.parseFromString(rendered, "text/html");
    const tagElement = doc.body.firstElementChild;
    if (!tagElement) {
      return rendered;
    }

    replaceDashesInTextNodes(tagElement);

    const tagName =
      typeof tag === "string" ? tag : tag?.name || tag?.slug || tag?.id || "";
    const tagOptions = tagMap[String(tagName).toLowerCase()];
    if (!tagOptions) {
      return tagElement.outerHTML;
    }

    const iconContainer = doc.createElement("span");
    iconContainer.className = "tag-icon";
    iconContainer.innerHTML = iconHTML(tagOptions.icon);
    iconContainer.style.color = "inherit";
    tagElement.classList.add("discourse-tag--tag-icons-style");
    tagElement.classList.add("discourse-tag--unified-icon");
    tagElement.style.setProperty("--color1", tagOptions.color || "");
    tagElement.style.setProperty("--color2", contrastColor(tagOptions.color));
    tagElement.prepend(iconContainer);

    if (enableColors && tagOptions.color) {
      tagElement.style.backgroundColor = tagOptions.color;
      const contrast = contrastColor(tagOptions.color) || "#fff";
      tagElement.style.color = contrast;
      iconContainer.style.color = contrast;
    }

    return tagElement.outerHTML;
  });
});
