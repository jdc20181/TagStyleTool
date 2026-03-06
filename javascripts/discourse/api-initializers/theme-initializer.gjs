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

function extractNamesFromUnknownList(input) {
  if (!Array.isArray(input)) {
    return [];
  }

  const names = [];
  input.forEach((item) => {
    if (item === null || item === undefined) {
      return;
    }

    if (typeof item === "string" || typeof item === "number") {
      names.push(String(item));
      return;
    }

    if (typeof item === "object") {
      names.push(item.name, item.slug, item.id, item.text);
    }
  });

  return names.filter(Boolean);
}

function getSidebarTagNamesFromDom() {
  if (typeof document === "undefined") {
    return [];
  }

  const names = [];
  document
    .querySelectorAll(".sidebar-section-link-wrapper[data-tag-name]")
    .forEach((el) => {
      const tagName = el.getAttribute("data-tag-name");
      if (tagName) {
        names.push(tagName);
      }
    });

  return names;
}

function getKnownSidebarTagNames(api) {
  const names = new Set();

  try {
    const site = api?.container?.lookup?.("service:site");
    const currentUser = api?.getCurrentUser?.();

    [
      site?.tags,
      site?.all_tags,
      site?.top_tags,
      site?.filterable_tags,
      site?.filterable_tag_names,
      site?.tag_list,
      currentUser?.sidebar_tags,
      currentUser?.sidebarTags,
    ].forEach((list) => {
      extractNamesFromUnknownList(list).forEach((name) =>
        names.add(String(name).trim().toLowerCase())
      );
    });
  } catch {
    // Optional source; continue with available data.
  }

  getSidebarTagNamesFromDom().forEach((name) =>
    names.add(String(name).trim().toLowerCase())
  );

  return names;
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
  const defaultTagIcon =
    String(settings.default_tag_icon || "tag").split("|")[0].trim() || "tag";
  const enableDefaultTagIcon = settings.enable_default_tag_icon !== false;
  const enableColors = !!settings.enable_colors_for_tag_labels;

  if (api.registerCustomTagSectionLinkPrefixIcon) {
    const registeredSidebarTagNames = new Set();
    const registerSidebarPrefixIcons = () => {
      const tagNames = new Set([
        ...Object.keys(tagMap),
        ...Array.from(getKnownSidebarTagNames(api)),
      ]);

      tagNames.forEach((rawTagName) => {
        const tagName = String(rawTagName || "").trim().toLowerCase();
        if (!tagName || registeredSidebarTagNames.has(tagName)) {
          return;
        }

        const tagOptions = tagMap[tagName];
        const prefixValue =
          tagOptions?.icon ||
          (enableDefaultTagIcon && defaultTagIcon ? defaultTagIcon : null);
        if (!prefixValue) {
          return;
        }

        api.registerCustomTagSectionLinkPrefixIcon({
          tagName,
          prefixValue,
          prefixColor: tagOptions?.color || undefined,
        });

        registeredSidebarTagNames.add(tagName);
      });
    };

    registerSidebarPrefixIcons();
    api.onPageChange?.(registerSidebarPrefixIcons);
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

    if (settings.remove_dashes_from_tags) {
      replaceDashesInTextNodes(tagElement);
    }

    const tagName =
      typeof tag === "string" ? tag : tag?.name || tag?.slug || tag?.id || "";
    const tagOptions = tagMap[String(tagName).toLowerCase()];
    let iconToUse = tagOptions?.icon;
    const colorToUse = tagOptions?.color || "";

    if (!iconToUse && enableDefaultTagIcon) {
      iconToUse = defaultTagIcon;
    }

    if (!iconToUse) {
      return tagElement.outerHTML;
    }

    const iconContainer = doc.createElement("span");
    iconContainer.className = "tag-icon";
    iconContainer.innerHTML = iconHTML(iconToUse);
    iconContainer.style.color = "inherit";
    tagElement.classList.add("discourse-tag--tag-icons-style");
    tagElement.classList.add("discourse-tag--unified-icon");
    tagElement.style.setProperty("--color1", colorToUse);
    tagElement.style.setProperty("--color2", contrastColor(colorToUse));
    tagElement.prepend(iconContainer);

    if (enableColors && colorToUse) {
      tagElement.style.backgroundColor = colorToUse;
      const contrast = contrastColor(colorToUse) || "#fff";
      tagElement.style.color = contrast;
      iconContainer.style.color = contrast;
    }

    return tagElement.outerHTML;
  });
});
