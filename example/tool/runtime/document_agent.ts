// The "document" agent: writes a document into the shared state while it
// streams, so the app can render it token by token (state rendering).
import { randomUUID } from "node:crypto";
import { EventType, type BaseEvent } from "@ag-ui/core";
import {
  BuiltInAgent,
  convertMessagesToVercelAISDKMessages,
  resolveModel,
} from "@copilotkit/runtime/v2";
import { streamText } from "ai";

/** What the agent says in the chat once the document is written. */
export const doneReply = "I updated the document.";

/** The system prompt for a run on a state whose document is [document]. */
export function documentPrompt(document: string): string {
  return (
    "You write and edit a document with the user. Reply with the complete " +
    "new document only: no preamble, no notes, no code fences. Keep what the " +
    "user did not ask to change, and use blank lines between paragraphs.\n\n" +
    `The current document is:\n<document>\n${document}\n</document>`
  );
}

/** The state of a run as an object, so its other keys are kept. */
export function stateOf(state: unknown): Record<string, unknown> {
  return state !== null && typeof state === "object" && !Array.isArray(state)
    ? (state as Record<string, unknown>)
    : {};
}

/**
 * Creates the document agent on [model]. The model's text is the new
 * document: each piece is sent as a STATE_SNAPSHOT of the document so far,
 * and the agent then says [doneReply] in the chat.
 *
 * A text stream is used instead of a tool's arguments because not every
 * provider streams tool arguments (Gemini sends them in one piece).
 */
export function documentAgent(model: string): BuiltInAgent {
  return new BuiltInAgent({
    type: "custom",
    factory: async function* (ctx): AsyncIterable<BaseEvent> {
      const base = stateOf(ctx.input.state);
      const current =
        typeof base.document === "string" ? base.document : "";
      const result = streamText({
        model: resolveModel(model),
        system: documentPrompt(current),
        messages: convertMessagesToVercelAISDKMessages(ctx.input.messages),
        abortSignal: ctx.abortSignal,
      });
      let document = "";
      for await (const part of result.fullStream) {
        if (part.type === "error") throw part.error;
        if (part.type !== "text-delta" || part.text.length === 0) continue;
        document += part.text;
        yield {
          type: EventType.STATE_SNAPSHOT,
          snapshot: { ...base, document },
        } as BaseEvent;
      }
      const messageId = randomUUID();
      yield {
        type: EventType.TEXT_MESSAGE_START,
        messageId,
        role: "assistant",
      } as BaseEvent;
      yield {
        type: EventType.TEXT_MESSAGE_CONTENT,
        messageId,
        delta: doneReply,
      } as BaseEvent;
      yield { type: EventType.TEXT_MESSAGE_END, messageId } as BaseEvent;
    },
  });
}
