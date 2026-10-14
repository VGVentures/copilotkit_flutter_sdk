// Local Copilot Runtime for the example app, based on the CopilotKit
// React Native quickstart. Start it with ../start_runtime.sh.
import { createServer } from "node:http";
import { networkInterfaces } from "node:os";
import { BuiltInAgent, CopilotRuntime } from "@copilotkit/runtime/v2";
import { createCopilotNodeListener } from "@copilotkit/runtime/v2/node";

const basePath = "/api/copilotkit";
const port = Number(process.env.PORT ?? 8200);
const model = process.env.COPILOTKIT_MODEL ?? "openai:gpt-5-mini";

const runtime = new CopilotRuntime({
  agents: {
    default: new BuiltInAgent({
      model,
      prompt: "You are a helpful assistant for a Flutter app.",
    }),
  },
});

function lanAddresses(): string[] {
  return Object.values(networkInterfaces())
    .flat()
    .filter((net) => net !== undefined && net.family === "IPv4" && !net.internal)
    .map((net) => net!.address);
}

createServer(createCopilotNodeListener({ runtime, basePath, cors: true })).listen(
  port,
  "0.0.0.0",
  () => {
    console.log(`Copilot Runtime (${model}) listening on:`);
    console.log(`  http://localhost:${port}${basePath}`);
    for (const address of lanAddresses()) {
      console.log(`  http://${address}:${port}${basePath}`);
    }
  },
);
