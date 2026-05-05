const extensionAPI = globalThis.chrome || globalThis.browser;

extensionAPI?.runtime?.onInstalled?.addListener(() => {
  extensionAPI.storage.sync.set({
    litrixEndpoint: "http://127.0.0.1:23122/mcp/web-import"
  });
});
