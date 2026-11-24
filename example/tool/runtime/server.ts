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
import { defaultUser, resolveLearningContainerId } from "./config.ts";

const basePath = "/api/copilotkit";
const port = Number(process.env.PORT ?? 8200);
const model = process.env.COPILOTKIT_MODEL ?? "openai:gpt-5-mini";

const agents = {
  default: new BuiltInAgent({
    model,
    prompt:
      "You are a helpful assistant for a Flutter app. The app shows the " +
      "user a todo list, kept in the application state as " +
      '{"todos": [{"title": string, "done": boolean}]}. When the user ' +
      "asks to add, finish or remove a todo, edit that list with the state " +
      "tools and keep the other items as they are.",
  }),
};

// With CPK_INTELLIGENCE_API_KEY the runtime records threads in Intelligence
// and assigns each one to a Learning container. Without it, it serves plain
// SSE, as before. The key is server-side only: keep it in the shell or in
// the git-ignored example/tool/.env.
const intelligenceApiKey = process.env.CPK_INTELLIGENCE_API_KEY;
const learningContainerId = intelligenceApiKey
  ? resolveLearningContainerId(process.env.CPK_INTELLIGENCE_LEARNING_CONTAINER_ID)
  : undefined;

const runtime = intelligenceApiKey
  ? new CopilotRuntime({
      agents,
      intelligence: new CopilotKitIntelligence({
        apiKey: intelligenceApiKey,
        // Must return the same id for every run of a thread, and before its
        // first run: a thread can't move to another container later.
        getLearningContainerId: () => learningContainerId,
      }),
      identifyUser: () => defaultUser,
    })
  : new CopilotRuntime({ agents });

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
    const mode = learningContainerId
      ? `Intelligence, Learning container "${learningContainerId}"`
      : "SSE";
    console.log(`Copilot Runtime (${model}, ${mode}) listening on:`);
    console.log(`  http://localhost:${port}${basePath}`);
    for (const address of lanAddresses()) {
      console.log(`  http://${address}:${port}${basePath}`);
    }
  },
);
