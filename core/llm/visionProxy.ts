/**
 * Vision Proxy — Route image messages through a Vision Language Model (VLM)
 * before sending to the main LLM.
 *
 * Flow:
 *   1. Scan messages for image content parts
 *   2. Send images to VLM (e.g., Qwen2.5-VL-32B) for text description
 *   3. Replace image parts with [Image Description: ...] text
 *   4. Return text-only messages for the main LLM (e.g., DeepSeek V4 Flash)
 *
 * This enables text-only LLMs to "understand" images via a multi-model pipeline,
 * maximizing context length (524K) while retaining visual understanding capability.
 */

import { ChatMessage, ImageMessagePart, MessagePart } from "..";

// ─── Types ───────────────────────────────────────────────────────────────────

export interface VisionProxyOptions {
  /** VLM endpoint (OpenAI-compatible), e.g. http://171.232.252.166:7002/v1 */
  endpoint: string;

  /** VLM model name, e.g. Qwen/Qwen2.5-VL-32B-Instruct */
  model: string;

  /** API key for VLM endpoint */
  apiKey?: string;

  /** Max tokens for VLM description response (default: 2048) */
  maxTokens?: number;

  /**
   * Prompt template for image description.
   * - "code": Optimized for code screenshots
   * - "ui": Optimized for UI/UX screenshots
   * - "diagram": Optimized for architecture/flowchart diagrams
   * - "auto": Generic all-purpose description
   * - string: Custom prompt template
   */
  promptTemplate?: "code" | "ui" | "diagram" | "auto" | string;

  /** Temperature for VLM (default: 0.2 for deterministic descriptions) */
  temperature?: number;

  /** Request timeout in ms (default: 30000) */
  timeout?: number;

  /** Enable/disable vision proxy (default: true when configured) */
  enabled?: boolean;
}

// ─── Prompt Templates ────────────────────────────────────────────────────────

const PROMPT_TEMPLATES: Record<string, string> = {
  code: `Describe this code screenshot in detail:
1. What programming language is shown?
2. Transcribe all visible code exactly as written
3. Note any error messages, highlights, or annotations
4. Describe the file name and line numbers if visible
Be concise but accurate. Prioritize code transcription.`,

  ui: `Describe this UI screenshot:
1. What application or webpage is shown?
2. Describe the layout (header, sidebar, content, footer)
3. List all visible text, buttons, and form elements
4. Note any error states, loading indicators, or unusual elements
Be concise and structured.`,

  diagram: `Describe this technical diagram:
1. What type of diagram is it? (flowchart, architecture, sequence, ER, etc.)
2. List all components/nodes and their labels
3. Describe the connections/relationships between components
4. Note any annotations, colors, or groupings
Be precise about the relationships and data flow.`,

  auto: `Describe this image in detail for a software development context.
If it contains code, transcribe the code exactly.
If it contains UI elements, describe the layout and visible text.
If it contains a diagram, describe components and their relationships.
Be concise but thorough.`,
};

// ─── Helper Functions ────────────────────────────────────────────────────────

/**
 * Check if a message contains image content parts
 */
function hasImageContent(content: string | MessagePart[]): boolean {
  if (typeof content === "string") return false;
  return content.some((part) => part.type === "imageUrl");
}

/**
 * Extract image parts from message content
 */
function extractImageParts(content: MessagePart[]): ImageMessagePart[] {
  return content.filter(
    (part) => part.type === "imageUrl",
  ) as ImageMessagePart[];
}

/**
 * Get the prompt template string based on option
 */
function getPromptTemplate(template?: string): string {
  if (!template) return PROMPT_TEMPLATES.auto;
  if (template in PROMPT_TEMPLATES) return PROMPT_TEMPLATES[template];
  // Custom template string
  return template;
}

/**
 * Call VLM to describe a single image
 */
async function describeImage(
  imageUrl: string,
  options: VisionProxyOptions,
  signal?: AbortSignal,
): Promise<string> {
  const endpoint = options.endpoint.replace(/\/$/, "");
  const url = `${endpoint}/chat/completions`;
  const promptText = getPromptTemplate(options.promptTemplate);

  const requestBody = {
    model: options.model,
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image_url",
            image_url: { url: imageUrl, detail: "high" },
          },
          {
            type: "text",
            text: promptText,
          },
        ],
      },
    ],
    max_tokens: options.maxTokens ?? 2048,
    temperature: options.temperature ?? 0.2,
    stream: false,
  };

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (options.apiKey) {
    headers["Authorization"] = `Bearer ${options.apiKey}`;
  }

  const controller = new AbortController();
  const timeout = options.timeout ?? 30000;

  // Combine external signal with timeout
  const timeoutId = setTimeout(() => controller.abort(), timeout);
  if (signal) {
    signal.addEventListener("abort", () => controller.abort());
  }

  try {
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => "Unknown error");
      console.warn(
        `[VisionProxy] VLM request failed (${response.status}): ${errorText}`,
      );
      return `[Image: VLM description failed — ${response.status}]`;
    }

    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;

    if (!content) {
      console.warn("[VisionProxy] VLM returned empty content");
      return "[Image: VLM returned empty description]";
    }

    return content.trim();
  } catch (error: any) {
    if (error.name === "AbortError") {
      console.warn("[VisionProxy] VLM request timed out or was aborted");
      return "[Image: VLM request timed out]";
    }
    console.warn(`[VisionProxy] VLM request error: ${error.message}`);
    return `[Image: VLM error — ${error.message}]`;
  } finally {
    clearTimeout(timeoutId);
  }
}

// ─── Main Export ─────────────────────────────────────────────────────────────

/**
 * Process messages through vision proxy.
 * Images are sent to VLM for description, then replaced with text.
 * Messages without images pass through unchanged.
 *
 * @param messages - Chat messages (internal Continue format)
 * @param options - Vision proxy configuration
 * @param signal - Optional abort signal
 * @returns Processed messages with images replaced by text descriptions
 */
export async function processMessagesWithVisionProxy(
  messages: ChatMessage[],
  options: VisionProxyOptions,
  signal?: AbortSignal,
): Promise<ChatMessage[]> {
  if (!options.enabled && options.enabled !== undefined) {
    return messages;
  }

  const result: ChatMessage[] = [];

  for (const message of messages) {
    // Only process user messages that have array content with images
    if (
      message.role === "user" &&
      Array.isArray(message.content) &&
      hasImageContent(message.content)
    ) {
      const processedParts: MessagePart[] = [];
      const imageParts = extractImageParts(message.content);

      // Process each part
      for (const part of message.content) {
        if (part.type === "imageUrl") {
          // Send image to VLM for description
          const description = await describeImage(
            (part as ImageMessagePart).imageUrl.url,
            options,
            signal,
          );
          processedParts.push({
            type: "text",
            text: `\n[Image Description]\n${description}\n[/Image Description]\n`,
          });
        } else {
          // Keep text parts as-is
          processedParts.push(part);
        }
      }

      result.push({ ...message, content: processedParts });
    } else {
      // Non-image messages pass through unchanged
      result.push(message);
    }
  }

  return result;
}
