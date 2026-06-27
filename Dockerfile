FROM linuxserver/code-server:4.126.0

# ---------------------------------------------------------------------------
# System deps
# jq is used by the init script to merge settings.json without clobbering
# existing user settings.
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Bake the GitHub Copilot VSIX into the image at build time.
#
# GitHub Copilot is not published to Open VSX (the default code-server
# registry), so we pull it directly from the VS Code Marketplace.
#
# The marketplace serves a gzip-encoded response; --compressed lets curl
# decompress it so the result is a valid ZIP/VSIX file.
#
# To pin a specific version, replace "latest" in the URL with the version
# number, e.g.: .../copilot/1.388.0/vspackage
# ---------------------------------------------------------------------------
RUN mkdir -p /app/extensions \
    && curl -fsSL --compressed \
       "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot/latest/vspackage" \
       -o /app/extensions/github.copilot.vsix

# ---------------------------------------------------------------------------
# Init script — runs at every container start via linuxserver's s6 hook dir.
# Installs the extension into /config/extensions (which is a volume, so it
# cannot be written at build time) and disables all preview/experimental
# settings derived from github.copilot/dist/main.js tag registry.
#
# The script is base64-encoded to avoid shell quoting issues with jq filters
# and bash variable references inside the Dockerfile RUN layer.
# To view/edit: base64 -d <<< "<value below>" or decode scripts/init-copilot.sh
# ---------------------------------------------------------------------------
RUN mkdir -p /custom-cont-init.d \
    && echo IyEvYmluL2Jhc2gKIyBSdW5zIGF0IGNvbnRhaW5lciBzdGFydHVwIHZpYSAvY3VzdG9tLWNvbnQtaW5pdC5kIChsaW51eHNlcnZlciBzNi1vdmVybGF5IGhvb2spLgojIC9jb25maWcgaXMgYSB2b2x1bWUgc28gZXh0ZW5zaW9uIGluc3RhbGwgYW5kIHNldHRpbmdzIG11c3QgaGFwcGVuIGF0IHJ1bnRpbWUuCgpzZXQgLWUKClZTSVg9Ii9hcHAvZXh0ZW5zaW9ucy9naXRodWIuY29waWxvdC52c2l4IgpFWFRFTlNJT05TX0RJUj0iL2NvbmZpZy9leHRlbnNpb25zIgpTRVRUSU5HU19GSUxFPSIvY29uZmlnL2RhdGEvVXNlci9zZXR0aW5ncy5qc29uIgoKIyAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0KIyBJbnN0YWxsIGV4dGVuc2lvbiAoaWRlbXBvdGVudCDigJQgc2tpcHMgaWYgYWxyZWFkeSBwcmVzZW50KQojIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQpta2RpciAtcCAiJEVYVEVOU0lPTlNfRElSIgoKaWYgISAvYXBwL2NvZGUtc2VydmVyL2Jpbi9jb2RlLXNlcnZlciBcCiAgICAgICAgLS1leHRlbnNpb25zLWRpciAiJEVYVEVOU0lPTlNfRElSIiBcCiAgICAgICAgLS1saXN0LWV4dGVuc2lvbnMgMj4vZGV2L251bGwgfCBncmVwIC1xaSAiZ2l0aHViLmNvcGlsb3QiOyB0aGVuCgogICAgZWNobyAiW2NvcGlsb3QtaW5pdF0gSW5zdGFsbGluZyBHaXRIdWIgQ29waWxvdC4uLiIKICAgIC9hcHAvY29kZS1zZXJ2ZXIvYmluL2NvZGUtc2VydmVyIFwKICAgICAgICAtLWV4dGVuc2lvbnMtZGlyICIkRVhURU5TSU9OU19ESVIiIFwKICAgICAgICAtLXVzZXItZGF0YS1kaXIgL2NvbmZpZy9kYXRhIFwKICAgICAgICAtLWluc3RhbGwtZXh0ZW5zaW9uICIkVlNJWCIgMj4mMQogICAgZWNobyAiW2NvcGlsb3QtaW5pdF0gRXh0ZW5zaW9uIGluc3RhbGxlZC4iCmVsc2UKICAgIGVjaG8gIltjb3BpbG90LWluaXRdIEdpdEh1YiBDb3BpbG90IGFscmVhZHkgaW5zdGFsbGVkIOKAlCBza2lwcGluZy4iCmZpCgojIC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQojIERpc2FibGUgYWxsIHByZXZpZXcvZXhwZXJpbWVudGFsIGZlYXR1cmVzLgojCiMgVGhpcyBsaXN0IHdhcyBkZXJpdmVkIGZyb20gZ2l0aHViLmNvcGlsb3QtMS4zODguMC9kaXN0L21haW4uanMg4oCUCiMgZXZlcnkgc2V0dGluZyByZWdpc3RlcmVkIHdpdGggdGFnczpbInByZXZpZXciXSBvciB0YWdzOlsiZXhwZXJpbWVudGFsIl0KIyAoaW5jbHVkaW5nICJvbkV4cCIgd2hpY2ggaXMgdGhlIEEvQiByb2xsb3V0IGZsYWcpLgojCiMgS2V5cyBhcmUgbWVyZ2VkIG9uIHRvcCBvZiBleGlzdGluZyBzZXR0aW5ncyBzbyB1bnJlbGF0ZWQgdXNlciBwcmVmZXJlbmNlcwojIGFyZSBwcmVzZXJ2ZWQuIFByZXZpZXcga2V5cyBhcmUgYWx3YXlzIGZvcmNlZCB0byBmYWxzZS9vZmYuCiMgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tCm1rZGlyIC1wICIkKGRpcm5hbWUgIiRTRVRUSU5HU19GSUxFIikiCgpFWElTVElORz0ie30iCmlmIFsgLWYgIiRTRVRUSU5HU19GSUxFIiBdOyB0aGVuCiAgICBFWElTVElORz0kKGNhdCAiJFNFVFRJTkdTX0ZJTEUiKQpmaQoKanEgLS1hcmdqc29uIGV4aXN0aW5nICIkRVhJU1RJTkciICckZXhpc3RpbmcgKyB7CiAgImdpdGh1Yi5jb3BpbG90Lm5leHRFZGl0U3VnZ2VzdGlvbnMuZW5hYmxlZCI6ICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90Lm5leHRFZGl0U3VnZ2VzdGlvbnMuYWxsb3dXaGl0ZXNwYWNlT25seUNoYW5nZXMiOiAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90Lm5leHRFZGl0U3VnZ2VzdGlvbnMuZml4ZXMiOiAgICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuYWdlbnQudGhpbmtpbmdUb29sIjogICAgICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuYWx0ZXJuYXRlR3B0UHJvbXB0LmVuYWJsZWQiOiAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuY29kZXNlYXJjaC5lbmFibGVkIjogICAgICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuY29waWxvdERlYnVnQ29tbWFuZC5lbmFibGVkIjogICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuZWRpdG9yLnRlbXBvcmFsQ29udGV4dC5lbmFibGVkIjogICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuZWRpdHMuc3VnZ2VzdFJlbGF0ZWRGaWxlc0ZvclRlc3RzIjogICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuZWRpdHMuc3VnZ2VzdFJlbGF0ZWRGaWxlc0Zyb21HaXRIaXN0b3J5IjogICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuZWRpdHMudGVtcG9yYWxDb250ZXh0LmVuYWJsZWQiOiAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuZXhlY3V0ZVByb21wdC5lbmFibGVkIjogICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuZ2VuZXJhdGVUZXN0cy5jb2RlTGVucyI6ICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQuaW1hZ2VVcGxvYWQuZW5hYmxlZCI6ICAgICAgICAgICAgICAgICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQubGFuZ3VhZ2VDb250ZXh0LmZpeC50eXBlc2NyaXB0LmVuYWJsZWQiOiAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQubGFuZ3VhZ2VDb250ZXh0LmlubGluZS50eXBlc2NyaXB0LmVuYWJsZWQiOiAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQubGFuZ3VhZ2VDb250ZXh0LnR5cGVzY3JpcHQuZW5hYmxlZCI6ICAgICAgICAgICAgZmFsc2UsCiAgImdpdGh1Yi5jb3BpbG90LmNoYXQubGFuZ3VhZ2VDb250ZXh0LnR5cGVzY3JpcHQuaW5jbHVkZURvY3VtZW50YXRpb24iOiBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5uZXdXb3Jrc3BhY2UudXNlQ29udGV4dDciOiAgICAgICAgICAgICAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5uZXdXb3Jrc3BhY2VDcmVhdGlvbi5lbmFibGVkIjogICAgICAgICAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5ub3RlYm9vay5lbmhhbmNlZE5leHRFZGl0U3VnZ2VzdGlvbnMuZW5hYmxlZCI6ICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5ub3RlYm9vay5mb2xsb3dDZWxsRXhlY3V0aW9uLmVuYWJsZWQiOiAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5yZXZpZXdBZ2VudC5lbmFibGVkIjogICAgICAgICAgICAgICAgICAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5yZXZpZXdTZWxlY3Rpb24uZW5hYmxlZCI6ICAgICAgICAgICAgICAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5zZXR1cFRlc3RzLmVuYWJsZWQiOiAgICAgICAgICAgICAgICAgICAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5zdGFydERlYnVnZ2luZy5lbmFibGVkIjogICAgICAgICAgICAgICAgICAgICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC5zdW1tYXJpemVBZ2VudENvbnZlcnNhdGlvbkhpc3RvcnkuZW5hYmxlZCI6ICAgICBmYWxzZSwKICAiZ2l0aHViLmNvcGlsb3QuY2hhdC51c2VSZXNwb25zZXNBcGkiOiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmYWxzZQp9JyA8PDwgJ251bGwnID4gIiRTRVRUSU5HU19GSUxFIgoKZWNobyAiW2NvcGlsb3QtaW5pdF0gUHJldmlldyBmZWF0dXJlcyBkaXNhYmxlZCAoMjggc2V0dGluZ3MpLiIK | base64 -d > /custom-cont-init.d/01-copilot.sh \
    && chmod +x /custom-cont-init.d/01-copilot.sh
