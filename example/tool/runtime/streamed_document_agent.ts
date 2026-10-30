// An agent that streams the `document` argument of its `write_document` tool
// into the application state, like the docs' `stream_document_state`: while
// the model writes the argument, every chunk becomes a STATE_SNAPSHOT, so the
// app renders the document token by token.
import { BuiltInAgent, defineTool } from "@copilotkit/runtime/v2";
import { EventType, type BaseEvent, type RunAgentInput } from "@ag-ui/client";
import { map, type Observable } from "rxjs";
import { z } from "zod";

const toolName = "write_document";

/** Reads the string value of `"document"` from partial JSON tool arguments. */
export function partialDocument(args: string): string | undefined {
  const match = /"document"\s*:\s*"/.exec(args);
  if (match === null) return undefined;
  let text = "";
  for (let i = match.index + match[0].length; i < args.length; i++) {
    const char = args[i];
    if (char === '"') break;
    if (char !== "\\") {
      text += char;
      continue;
    }
    const next = args[i + 1];
    if (next === undefined) break; // A lone backslash: the escape is cut off.
    i++;
    if (next === "u") {
      const hex = args.slice(i + 1, i + 5);
      if (hex.length < 4) break; // A cut-off unicode escape.
      text += String.fromCharCode(parseInt(hex, 16));
      i += 4;
    } else {
      text += { n: "\n", t: "\t", r: "\r", b: "\b", f: "\f" }[next] ?? next;
    }
  }
  return text;
}

export class StreamedDocumentAgent extends BuiltInAgent {
  run(input: RunAgentInput): Observable<BaseEvent> {
    let state: Record<string, unknown> = { ...(input.state ?? {}) };
    let writing: string | undefined; // Id of the `write_document` call.
    let args = "";
    return super.run(input).pipe(
      map((event) => {
        const e = event as BaseEvent & Record<string, any>;
        switch (e.type) {
          case EventType.STATE_SNAPSHOT:
            state = { ...e.snapshot };
            return event;
          case EventType.TOOL_CALL_START:
            if (e.toolCallName === toolName) {
              writing = e.toolCallId;
              args = "";
            }
            return event;
          case EventType.TOOL_CALL_ARGS: {
            if (e.toolCallId !== writing) return event;
            args += e.delta;
            const document = partialDocument(args);
            if (document === undefined) return event;
            state = { ...state, document };
            return { type: EventType.STATE_SNAPSHOT, snapshot: state } as BaseEvent;
          }
          default:
            return event;
        }
      }),
    );
  }

  clone(): StreamedDocumentAgent {
    return new StreamedDocumentAgent(
      (this as unknown as { config: ConstructorParameters<typeof BuiltInAgent>[0] }).config,
    );
  }
}

/** The tool the model calls to write the document. */
export const writeDocument = defineTool({
  name: toolName,
  description:
    "Writes the document the user sees, replacing the current one. Pass " +
    "the complete text.",
  parameters: z.object({ document: z.string().describe("The full text.") }),
  execute: async () => "The document was written.",
});
