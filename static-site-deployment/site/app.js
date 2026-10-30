const output = document.getElementById("output");
const buildIdElement = document.getElementById("build-id");

function currentBuildIdFromMeta() {
  const meta = document.querySelector('meta[name="build-id"]');
  return meta ? meta.content : "unknown";
}

buildIdElement.textContent = currentBuildIdFromMeta();

document.getElementById("check").addEventListener("click", async () => {
  output.textContent = "Requesting...";

  try {
    const response = await fetch(`/?probe=${Date.now()}`);
    const html = await response.text();
    const match = html.match(/name="build-id"\s+content="([^"]+)"/);
    const served = match ? match[1] : "unknown";

    output.textContent = [
      `Page build:  ${currentBuildIdFromMeta()}`,
      `Edge build:  ${served}`,
      `HTTP status: ${response.status}`,
      `x-cache:     ${response.headers.get("x-cache") || "n/a"}`,
      `age:         ${response.headers.get("age") || "n/a"}`,
      `pop:         ${response.headers.get("x-amz-cf-pop") || "n/a"}`,
    ].join("\n");
  } catch (error) {
    output.textContent = `Request failed: ${error}`;
  }
});
