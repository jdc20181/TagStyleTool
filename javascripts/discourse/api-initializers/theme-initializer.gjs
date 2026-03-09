import { apiInitializer } from "discourse/lib/api";
import { iconHTML } from "discourse/lib/icon-library";
import { defaultRenderTag } from "discourse/lib/render-tag";

function normalizeIconName(iconName) {
  if (!iconName || typeof iconName !== "string") {
    return "";
  }
  return iconName.trim();
}

function normalizeLookupKey(value) {
  return String(value || "").trim().toLowerCase();
}

function mapLookupWithSlugVariants(map, value) {
  const key = normalizeLookupKey(value);
  if (!key) {
    return null;
  }

  if (map[key]) {
    return map[key];
  }

  const dashed = key.replace(/\s+/g, "-");
  if (map[dashed]) {
    return map[dashed];
  }

  const spaced = key.replace(/-/g, " ");
  if (map[spaced]) {
    return map[spaced];
  }

  return null;
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

    const tagName = normalizeLookupKey(parts[0]);
    const iconName = normalizeIconName(parts[1]);
    const color = (parts[2] || "").trim();

    if (tagName && iconName) {
      map[tagName] = { icon: iconName, color };
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
      if (item.name) {
        names.push(item.name);
      } else if (item.slug) {
        names.push(item.slug);
      } else if (item.text) {
        names.push(item.text);
      }
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
        names.add(normalizeLookupKey(name))
      );
    });
  } catch {
    // TODO - Consider adding some sort of logging, if theres an error here, it will just sillently fail. 
  }

  getSidebarTagNamesFromDom().forEach((name) =>
    names.add(normalizeLookupKey(name))
  );

  return names;
}

function resolveTagVisualOptions({
  tagName,
  tagMap,
  defaultTagIcon,
  enableDefaultTagIcon,
}) {
  const key = normalizeLookupKey(tagName);
  const tagOptions = tagMap[key];
  let iconToUse = tagOptions?.icon;
  const colorToUse = tagOptions?.color || "";

  if (!iconToUse && enableDefaultTagIcon) {
    iconToUse = defaultTagIcon;
  }

  return { iconToUse, colorToUse };
}

function replaceDashesInTextNodes(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
  let node = walker.nextNode();
  while (node) {
    node.nodeValue = node.nodeValue.replace(/-/g, " ");
    node = walker.nextNode();
  }
}

function normalizeHexColor(value) {
  if (!value) {
    return "";
  }

  let hex = String(value).trim().replace(/^#/, "");
  if (hex.length === 3) {
    hex = hex
      .split("")
      .map((char) => char + char)
      .join("");
  }

  if (!/^[0-9a-fA-F]{6}$/.test(hex)) {
    return "";
  }

  return `#${hex.toUpperCase()}`;
}

function parseBulkTagNames(input) {
  const values = String(input || "")
    .split(/[\n|,]+/)
    .map((value) => normalizeLookupKey(value))
    .filter((value) => value && !/^\d+$/.test(value));

  return Array.from(new Set(values));
}

function buildBulkEntriesString({ bulkTagsValue, iconValue, colorValue }) {
  const tags = parseBulkTagNames(bulkTagsValue);
  const icon = normalizeIconName(iconValue);
  const color = normalizeHexColor(colorValue);

  if (!tags.length || !icon) {
    return "";
  }

  const entries = tags.map((tag) => `${tag},${icon},${color || ""}`);
  return entries.join("|") + "|";
}

let cachedTagGroups = null;

function getTagGroupsFromSite(api) {
  const site = api?.container?.lookup?.("service:site");
  return Array.isArray(site?.tag_groups)
    ? site.tag_groups
    : Array.isArray(site?.tagGroups)
      ? site.tagGroups
      : [];
}

function findTagGroupMatch(groups, key) {
  if (!Array.isArray(groups) || !key) {
    return null;
  }

  return (
    groups.find((group) => {
      const groupKeys = [
        normalizeLookupKey(group?.name),
        normalizeLookupKey(group?.slug),
        normalizeLookupKey(group?.id),
      ];
      return groupKeys.includes(key);
    }) || null
  );
}

function extractTagNamesFromGroup(group) {
  if (!group) {
    return [];
  }

  const tags = [
    ...extractNamesFromUnknownList(group?.tags),
    ...extractNamesFromUnknownList(group?.tag_names),
    ...extractNamesFromUnknownList(group?.tagNames),
    ...extractNamesFromUnknownList(group?.tag_list),
    ...extractNamesFromUnknownList(group?.tagList),
  ]
    .map((value) => normalizeLookupKey(value))
    .filter((value) => value && !/^\d+$/.test(value));

  return Array.from(new Set(tags));
}

async function getTagGroupsFromApi() {
  if (Array.isArray(cachedTagGroups)) {
    return cachedTagGroups;
  }

  try {
    const response = await fetch("/tag_groups.json", {
      credentials: "same-origin",
    });

    if (!response.ok) {
      return [];
    }

    const payload = await response.json();
    cachedTagGroups = Array.isArray(payload?.tag_groups)
      ? payload.tag_groups
      : Array.isArray(payload?.tagGroups)
        ? payload.tagGroups
        : [];
    return cachedTagGroups;
  } catch {
    return [];
  }
}

async function getTagGroupTagsByName(api, groupName) {
  const key = normalizeLookupKey(groupName);
  if (!key) {
    return [];
  }

  try {
    const siteGroups = getTagGroupsFromSite(api);
    const siteMatch = findTagGroupMatch(siteGroups, key);
    if (siteMatch) {
      return extractTagNamesFromGroup(siteMatch);
    }

    const apiGroups = await getTagGroupsFromApi();
    const apiMatch = findTagGroupMatch(apiGroups, key);
    if (apiMatch) {
      return extractTagNamesFromGroup(apiMatch);
    }

    return [];
  } catch {
    return [];
  }
}

async function copyText(text) {
  if (!text) {
    return false;
  }

  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

function getLocalIconCandidates() {
  const names = new Set();

  const addIcon = (iconName) => {
    const normalized = normalizeIconName(iconName);
    if (normalized) {
      names.add(normalized);
    }
  };

  String(settings.svg_icons || "")
    .split("|")
    .forEach((iconName) => addIcon(iconName));

  String(settings.default_tag_icon || "")
    .split("|")
    .forEach((iconName) => addIcon(iconName));

  String(settings.tag_icon_list || "")
    .split("|")
    .forEach((entry) => {
      const parts = entry.split(",");
      addIcon(parts[1]);
    });

  return Array.from(names);
}

async function searchFontAwesomeIconsGraphQL(queryText, options = {}) {
  const query = String(queryText || "").trim();
  if (!query) {
    return [];
  }

  const endpoint = String(
    options.endpoint || "https://api.fontawesome.com"
  ).trim();
  if (!endpoint) {
    return [];
  }

  const version = String(options.version || "7.x").trim() || "7.x";
  const first = Number(options.first || 30) || 30;

  const requestBody = {
    query: `
      query SearchIcons($version: String!, $query: String!, $first: Int!) {
        search(version: $version, query: $query, first: $first) {
          id
          label
        }
      }
    `,
    variables: {
      version,
      query,
      first,
    },
  };

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      throw new Error(`Search request failed (${response.status})`);
    }

    const payload = await response.json();
    if (Array.isArray(payload?.errors) && payload.errors.length) {
      throw new Error(payload.errors[0]?.message || "GraphQL query failed");
    }

    const matches = Array.isArray(payload?.data?.search)
      ? payload.data.search
      : [];
    const names = matches
      .map((item) => normalizeIconName(item?.id))
      .filter(Boolean);

    return Array.from(new Set(names));
  } catch (error) {
    throw error;
  }
}

function mountTagStyleBuilder(api) {
  if (typeof document === "undefined") {
    return;
  }

  const existing = document.getElementById("tag-style-tool-builder");
  if (existing) {
    return;
  }

  const root = document.createElement("div");
  root.id = "tag-style-tool-builder";
  root.className = "tag-style-tool-builder";
  const enableIconSearch = !!settings.enable_icon_search_in_style_builder;
  const iconSearchVersion =
    String(settings.font_awesome_graphql_version || "7.x").trim() || "7.x";
  const iconSearchEndpoint =
    String(
      settings.font_awesome_graphql_endpoint || "https://api.fontawesome.com"
    ).trim() || "https://api.fontawesome.com";
  const localIconCandidates = getLocalIconCandidates();

  const trigger = document.createElement("button");
  trigger.type = "button";
  trigger.className = "tag-style-tool-builder__trigger btn btn-primary";
  trigger.textContent = "Tag Style Builder";
  root.appendChild(trigger);

  const panel = document.createElement("div");
  panel.className = "tag-style-tool-builder__panel";
  panel.hidden = true;
  panel.innerHTML = `
    <div class="tag-style-tool-builder__row">
      <label>Name</label>
      <input class="tag-style-tool-builder__name" type="text" placeholder="bugs" />
    </div>
    <div class="tag-style-tool-builder__row">
      <label>Icon</label>
      <div class="tag-style-tool-builder__icon-input-wrap">
        <input class="tag-style-tool-builder__icon" type="text" placeholder="gavel" />
        ${
          enableIconSearch
            ? '<button type="button" class="btn btn-default tag-style-tool-builder__icon-browse">Browse Icons</button>'
            : ""
        }
      </div>
      ${
        enableIconSearch
          ? `
      <div class="tag-style-tool-builder__icon-browser" hidden>
        <div class="tag-style-tool-builder__icon-search-controls">
          <input class="tag-style-tool-builder__icon-search-input" type="text" placeholder="Search icon name (e.g. gavel)" />
          <button type="button" class="btn btn-default tag-style-tool-builder__icon-search-button">Search</button>
        </div>
        <div class="tag-style-tool-builder__icon-search-results"></div>
      </div>
      `
          : ""
      }
    </div>
    <div class="tag-style-tool-builder__row">
      <label>Color</label>
      <input class="tag-style-tool-builder__color" type="color" value="#52C50C" />
    </div>
    <div class="tag-style-tool-builder__row">
      <label>Hex</label>
      <input class="tag-style-tool-builder__hex" type="text" value="#52C50C" />
    </div>
    <div class="tag-style-tool-builder__row">
      <label>Bulk Tags (comma, pipe, or new line)</label>
      <textarea class="tag-style-tool-builder__bulk" rows="5" placeholder="tag-one|tag-two"></textarea>
    </div>
    <div class="tag-style-tool-builder__row">
      <label>Generated</label>
      <input class="tag-style-tool-builder__generated" type="text" readonly />
    </div>
    <div class="tag-style-tool-builder__actions">
      <button type="button" class="btn btn-default tag-style-tool-builder__load-group">Load Group Tags</button>
      <button type="button" class="btn btn-default tag-style-tool-builder__copy-bulk">Copy Bulk Tags</button>
      <button type="button" class="btn btn-default tag-style-tool-builder__copy">Copy</button>
      <button type="button" class="btn btn-default tag-style-tool-builder__close">Close</button>
    </div>
    <div class="tag-style-tool-builder__status"></div>
  `;
  root.appendChild(panel);

  const isBuilderRoute = () => {
    const path = String(window?.location?.pathname || "");
    return (
      path.includes("/admin/customize/components/") ||
      path.includes("/admin/config/customize/components/")
    );
  };

  const isTagIconListCandidate = (value) => {
    const normalized = normalizeLookupKey(value).replace(/[\s-]+/g, "_");
    return (
      normalized === "tag_icon_list" || normalized.includes("tag_icon_list")
    );
  };

  const findBuilderAnchor = () => {
    const settingWrappers = Array.from(
      document.querySelectorAll(
        "[data-setting], [data-setting-name], [data-setting-key], .setting, .control-group"
      )
    );

    const matchedWrapper = settingWrappers.find((el) => {
      const candidates = [
        el.getAttribute("data-setting"),
        el.getAttribute("data-setting-name"),
        el.getAttribute("data-setting-key"),
        el.id,
      ].filter(Boolean);
      return candidates.some((candidate) => isTagIconListCandidate(candidate));
    });

    if (matchedWrapper) {
      return matchedWrapper;
    }

    const fields = Array.from(
      document.querySelectorAll("textarea, input, select, label")
    );
    const matchedField = fields.find((el) => {
      const section = el.closest(
        "[data-setting], [data-setting-name], [data-setting-key], .setting, .control-group"
      );
      const candidates = [
        el.getAttribute("name"),
        el.getAttribute("id"),
        el.getAttribute("for"),
        el.getAttribute("data-setting"),
        el.getAttribute("data-setting-name"),
        el.getAttribute("data-setting-key"),
        section?.getAttribute("data-setting"),
        section?.getAttribute("data-setting-name"),
        section?.getAttribute("data-setting-key"),
      ].filter(Boolean);

      return candidates.some((candidate) => isTagIconListCandidate(candidate));
    });

    if (!matchedField) {
      return null;
    }

    return (
      matchedField.closest("[data-setting]") ||
      matchedField.closest(".setting") ||
      matchedField.closest(".control-group") ||
      matchedField
    );
  };

  const findFallbackMountParent = () => {
    const selectors = [
      ".admin-detail .settings",
      ".admin-detail .theme-settings",
      ".admin-detail",
      ".admin-content .settings",
      ".admin-content",
      "main",
    ];

    return (
      selectors
        .map((selector) => document.querySelector(selector))
        .find(Boolean) || null
    );
  };

  const mountInline = () => {
    if (!isBuilderRoute()) {
      root.remove();
      return;
    }

    const anchor = findBuilderAnchor();
    if (anchor && anchor.parentElement) {
      if (root.parentElement !== anchor.parentElement) {
        anchor.parentElement.insertBefore(root, anchor);
        return;
      }

      if (root.nextElementSibling !== anchor) {
        anchor.parentElement.insertBefore(root, anchor);
      }
      return;
    }

    const fallbackParent = findFallbackMountParent();
    if (!fallbackParent) {
      return;
    }

    if (root.parentElement !== fallbackParent) {
      fallbackParent.prepend(root);
    }
  };

  const mountInlineWithRetries = (attemptsLeft = 20) => {
    mountInline();
    if (root.isConnected || attemptsLeft <= 0) {
      return;
    }

    setTimeout(() => mountInlineWithRetries(attemptsLeft - 1), 150);
  };

  mountInlineWithRetries();
  const nameInput = panel.querySelector(".tag-style-tool-builder__name");
  const iconInput = panel.querySelector(".tag-style-tool-builder__icon");
  const iconBrowseButton = panel.querySelector(
    ".tag-style-tool-builder__icon-browse"
  );
  const iconBrowser = panel.querySelector(".tag-style-tool-builder__icon-browser");
  const iconSearchInput = panel.querySelector(
    ".tag-style-tool-builder__icon-search-input"
  );
  const iconSearchButton = panel.querySelector(
    ".tag-style-tool-builder__icon-search-button"
  );
  const iconSearchResults = panel.querySelector(
    ".tag-style-tool-builder__icon-search-results"
  );
  const colorInput = panel.querySelector(".tag-style-tool-builder__color");
  const hexInput = panel.querySelector(".tag-style-tool-builder__hex");
  const bulkInput = panel.querySelector(".tag-style-tool-builder__bulk");
  const generatedInput = panel.querySelector(".tag-style-tool-builder__generated");
  const status = panel.querySelector(".tag-style-tool-builder__status");
  const loadGroupButton = panel.querySelector(".tag-style-tool-builder__load-group");
  const copyBulkButton = panel.querySelector(".tag-style-tool-builder__copy-bulk");
  const copyButton = panel.querySelector(".tag-style-tool-builder__copy");
  const closeButton = panel.querySelector(".tag-style-tool-builder__close");

  const showStatus = (message) => {
    status.textContent = message;
  };

  const defaultIcon =
    String(settings.default_tag_icon || "tag").split("|")[0].trim() || "tag";
  iconInput.value = defaultIcon;

  const getCurrentEntry = () => {
    const name = normalizeLookupKey(nameInput.value);
    const icon = normalizeIconName(iconInput.value);
    const color = normalizeHexColor(hexInput?.value || colorInput.value);

    if (!name || !icon) {
      return "";
    }

    return `${name},${icon},${color || ""}`;
  };

  const updateGeneratedField = () => {
    const bulkValue = bulkInput?.value || "";
    const bulkEntries = buildBulkEntriesString({
      bulkTagsValue: bulkValue,
      iconValue: iconInput.value,
      colorValue: hexInput?.value || colorInput.value,
    });
    generatedInput.value = bulkEntries || getCurrentEntry();
  };

  const renderIconSearchResults = (names) => {
    if (!iconSearchResults) {
      return;
    }

    iconSearchResults.innerHTML = "";
    names.forEach((name) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "btn btn-default tag-style-tool-builder__icon-result";
      button.textContent = name;
      button.addEventListener("click", () => {
        iconInput.value = name;
        updateGeneratedField();
        showStatus(`Selected icon ${name}.`);
        if (iconBrowser) {
          iconBrowser.hidden = true;
        }
      });
      iconSearchResults.appendChild(button);
    });
  };

  const runIconSearch = async () => {
    if (!enableIconSearch || !iconSearchInput || !iconSearchButton) {
      return;
    }

    const query = iconSearchInput.value.trim();
    const queryLower = query.toLowerCase();
    if (query.length < 2) {
      showStatus("Enter at least 2 characters to search icons.");
      if (iconSearchResults) {
        iconSearchResults.innerHTML = "";
      }
      return;
    }

    iconSearchButton.disabled = true;
    showStatus(`Searching Font Awesome for "${query}"...`);

    let remoteNames = [];
    let remoteError = "";
    try {
      remoteNames = await searchFontAwesomeIconsGraphQL(query, {
        endpoint: iconSearchEndpoint,
        version: iconSearchVersion,
        first: 40,
      });
    } catch (error) {
      remoteError = String(error?.message || "unknown error");
    }

    iconSearchButton.disabled = false;

    const localNames = localIconCandidates
      .filter((name) => String(name).toLowerCase().includes(queryLower))
      .slice(0, 40);
    const names = Array.from(new Set([...remoteNames, ...localNames])).slice(
      0,
      40
    );

    if (!names.length) {
      showStatus(
        remoteError
          ? `No matches. API unavailable: ${remoteError}`
          : "No icon matches returned."
      );
      if (iconSearchResults) {
        iconSearchResults.innerHTML = "";
      }
      return;
    }

    renderIconSearchResults(names);
    showStatus(
      remoteError
        ? `Found ${names.length} local icon(s). API unavailable: ${remoteError}`
        : `Found ${names.length} icons.`
    );
  };

  let iconSearchDebounce = null;

  const togglePanel = (visible) => {
    panel.hidden = !visible;
    if (visible) {
      updateGeneratedField();
      showStatus("");
      nameInput.focus();
    } else if (iconBrowser) {
      iconBrowser.hidden = true;
    }
  };

  [nameInput, iconInput, hexInput, bulkInput].forEach(
    (input) => {
      input?.addEventListener("input", updateGeneratedField);
      input?.addEventListener("change", updateGeneratedField);
    }
  );

  colorInput?.addEventListener("change", () => {
    if (!hexInput) {
      return;
    }
    const normalized = normalizeHexColor(colorInput.value);
    if (!normalized) {
      return;
    }
    colorInput.value = normalized;
    hexInput.value = normalized;
    updateGeneratedField();
  });

  hexInput?.addEventListener("change", () => {
    const normalized = normalizeHexColor(hexInput.value);
    if (!normalized) {
      return;
    }
    hexInput.value = normalized;
    colorInput.value = normalized;
  });

  loadGroupButton?.addEventListener("click", async () => {
    const groupName = normalizeLookupKey(nameInput.value);
    if (!groupName) {
      showStatus("Enter a tag group name first.");
      return;
    }

    const tags = await getTagGroupTagsByName(api, groupName);
    if (!tags.length) {
      showStatus("No tags found for that group.");
      return;
    }

    if (bulkInput) {
      bulkInput.value = tags.join("|");
    }
    updateGeneratedField();
    showStatus(`Loaded ${tags.length} tag(s) into Bulk Tags.`);
  });

  copyBulkButton?.addEventListener("click", async () => {
    const bulkEntries = buildBulkEntriesString({
      bulkTagsValue: bulkInput?.value || "",
      iconValue: iconInput.value,
      colorValue: hexInput?.value || colorInput.value,
    });

    if (!bulkEntries) {
      showStatus("Bulk Tags, icon, and color are required for bulk copy.");
      return;
    }

    const copied = await copyText(bulkEntries);
    if (copied && bulkInput) {
      bulkInput.value = "";
      updateGeneratedField();
    }
    showStatus(copied ? "Copied expanded bulk entries." : "Could not copy automatically.");
  });

  trigger.addEventListener("click", () => {
    togglePanel(panel.hidden);
  });

  closeButton.addEventListener("click", () => {
    togglePanel(false);
  });

  iconBrowseButton?.addEventListener("click", () => {
    if (!iconBrowser) {
      return;
    }

    iconBrowser.hidden = !iconBrowser.hidden;
    if (!iconBrowser.hidden) {
      iconSearchInput?.focus();
    }
  });

  iconSearchButton?.addEventListener("click", runIconSearch);

  iconSearchInput?.addEventListener("input", () => {
    if (iconSearchDebounce) {
      clearTimeout(iconSearchDebounce);
    }
    iconSearchDebounce = setTimeout(runIconSearch, 250);
  });

  iconSearchInput?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      runIconSearch();
    }
  });

  copyButton.addEventListener("click", async () => {
    const entry = generatedInput.value || getCurrentEntry();
    if (!entry) {
      showStatus("Enter a name and icon first.");
      return;
    }

    const copied = await copyText(entry);
    showStatus(copied ? "Copied entry." : "Could not copy automatically.");
  });

  const routeManager = api?.container?.lookup?.("service:router");
  routeManager?.on?.("routeDidChange", () => {
    mountInlineWithRetries();
  });

  api.onPageChange?.(() => {
    mountInlineWithRetries();
  });
}

export default apiInitializer((api) => {
  const tagMap = parseTagIconList(settings.tag_icon_list || "");

  const defaultTagIcon =
    String(settings.default_tag_icon || "tag").split("|")[0].trim() || "tag";
  const enableDefaultTagIcon = settings.enable_default_tag_icon !== false;
  const enableColors = !!settings.enable_colors_for_tag_labels;
  mountTagStyleBuilder(api);

  if (api.registerCustomTagSectionLinkPrefixIcon) {
    const registeredSignatureByTag = new Map();
    const registerSidebarPrefixIcons = () => {
      const tagNames = new Set([
        ...Object.keys(tagMap),
        ...Array.from(getKnownSidebarTagNames(api)),
      ]);

      tagNames.forEach((rawTagName) => {
        const tagName = normalizeLookupKey(rawTagName);
        if (!tagName) {
          return;
        }

        const { iconToUse, colorToUse } = resolveTagVisualOptions({
          tagName,
          tagMap,
          defaultTagIcon,
          enableDefaultTagIcon,
        });

        if (!iconToUse) {
          return;
        }

        const signature = `${iconToUse}|${colorToUse || ""}`;
        if (registeredSignatureByTag.get(tagName) === signature) {
          return;
        }

        api.registerCustomTagSectionLinkPrefixIcon({
          tagName,
          prefixValue: iconToUse,
          prefixColor: colorToUse || undefined,
        });

        registeredSignatureByTag.set(tagName, signature);
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
    const { iconToUse, colorToUse } = resolveTagVisualOptions({
      tagName,
      tagMap,
      defaultTagIcon,
      enableDefaultTagIcon,
    });

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


