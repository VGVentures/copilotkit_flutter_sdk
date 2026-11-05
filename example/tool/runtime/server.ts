// Local Copilot Runtime for the example app, based on the CopilotKit
// React Native quickstart. Start it with ../start_runtime.sh.
import { createServer } from "node:http";
import { networkInterfaces } from "node:os";
import {
  BuiltInAgent,
  CopilotKitIntelligence,
  CopilotRuntime,
} from "@copilotkit/runtime/v2";
import { createCopilotNodeListener } from "@copilotkit/runtime/v2/node";

const basePath = "/api/copilotkit";
const port = Number(process.env.PORT ?? 8200);
const model = process.env.COPILOTKIT_MODEL ?? "openai:gpt-5-mini";

// Intelligence mode (managed threads, Learning, Memories) turns on only when
// the project key is set, so without it this stays a plain SSE runtime. The key
// is server-side only: keep it in example/tool/.env, never in the Flutter app.
const intelligenceKey = process.env.CPK_INTELLIGENCE_API_KEY;
const intelligence = intelligenceKey
  ? {
      intelligence: new CopilotKitIntelligence({ apiKey: intelligenceKey }),
      // The example has no sign-in, so every request is one local user.
      identifyUser: () => ({ id: "example-user", name: "Example User" }),
    }
  : {};

const runtime = new CopilotRuntime({
  ...intelligence,
  agents: {
    default: new BuiltInAgent({
      model,
      prompt:
        "You are a helpful assistant for a Flutter app. The app shows the " +
        "user a todo list, kept in the application state as " +
        '{"todos": [{"title": string, "done": boolean}]}. When the user ' +
        "asks to add, finish or remove a todo, edit that list with the state " +
        "tools and keep the other items as they are.",
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
    console.log(
      `Copilot Runtime (${model}, ${intelligenceKey ? "intelligence" : "sse"} mode) listening on:`,
    );
    console.log(`  http://localhost:${port}${basePath}`);
    for (const address of lanAddresses()) {
      console.log(`  http://${address}:${port}${basePath}`);
    }
  },
);
