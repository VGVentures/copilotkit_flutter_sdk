// Local Copilot Runtime for the example app, based on the CopilotKit
// React Native quickstart. Start it with ../start_runtime.sh.
import { createServer } from "node:http";
import { networkInterfaces } from "node:os";
import { CopilotRuntime } from "@copilotkit/runtime/v2";
import { createCopilotNodeListener } from "@copilotkit/runtime/v2/node";
import { StreamedDocumentAgent, writeDocument } from "./streamed_document_agent.ts";

const basePath = "/api/copilotkit";
const port = Number(process.env.PORT ?? 8200);
const model = process.env.COPILOTKIT_MODEL ?? "openai:gpt-5-mini";

const runtime = new CopilotRuntime({
  agents: {
    default: new StreamedDocumentAgent({
      model,
      tools: [writeDocument],
      prompt:
        "You are a helpful assistant for a Flutter app. The app shows the " +
        "user a todo list, kept in the application state as " +
        '{"todos": [{"title": string, "done": boolean}]}. When the user ' +
        "asks to add, finish or remove a todo, edit that list with the state " +
        "tools and keep the other items as they are. The state also holds " +
        'the document the user sees, as {"document": string}. To write or ' +
        "rewrite it, call write_document with the complete text, and start " +
        "from the document in the state, because the user may have edited " +
        "it.",
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
