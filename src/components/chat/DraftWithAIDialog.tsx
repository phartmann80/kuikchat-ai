import { useEffect, useRef, useState, type RefObject } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Sparkles, Send, Loader2, Copy, Check, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { supabase } from "@/integrations/supabase/client";
import { requestDraftGeneration } from "@/lib/draftWithAi";

interface DraftWithAIDialogProps {
  open: boolean;
  onClose: () => void;
  onInsert?: (text: string) => void;
  /** Element that should receive focus when the dialog closes. */
  returnFocusRef?: RefObject<HTMLElement | null>;
}

type LocalMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
};

export const DraftWithAIDialog = ({
  open,
  onClose,
  onInsert,
  returnFocusRef,
}: DraftWithAIDialogProps) => {
  const [input, setInput] = useState("");
  const [messages, setMessages] = useState<LocalMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [lastPrompt, setLastPrompt] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const abortRef = useRef<AbortController | null>(null);

  const resetLocalState = () => {
    abortRef.current?.abort();
    abortRef.current = null;
    setInput("");
    setMessages([]);
    setIsLoading(false);
    setError(null);
    setCopiedId(null);
    setLastPrompt(null);
  };

  useEffect(() => {
    if (open) {
      resetLocalState();
    }
  }, [open]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isLoading]);

  const handleOpenChange = (nextOpen: boolean) => {
    if (!nextOpen) {
      resetLocalState();
      onClose();
      // Return focus after Radix finishes unmount/focus restore cycle.
      window.setTimeout(() => {
        returnFocusRef?.current?.focus();
      }, 0);
    }
  };

  const generateDraft = async (promptRaw: string) => {
    if (isLoading) return;
    const prompt = promptRaw.trim();
    if (!prompt) return;

    setInput("");
    setLastPrompt(prompt);
    setError(null);

    const userMsg: LocalMessage = {
      id: `local-user-${crypto.randomUUID()}`,
      role: "user",
      content: prompt,
    };
    setMessages([userMsg]);
    setIsLoading(true);

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        throw Object.assign(new Error("Authentication required to draft with AI."), {
          code: "UNAUTHORIZED",
        });
      }

      const data = await requestDraftGeneration({
        supabaseUrl: import.meta.env.VITE_SUPABASE_URL,
        accessToken: session.access_token,
        prompt,
        signal: controller.signal,
      });

      if (controller.signal.aborted) return;

      setMessages([
        userMsg,
        {
          id: `local-assistant-${data.request_id}`,
          role: "assistant",
          content: data.message.content,
        },
      ]);
    } catch (err: unknown) {
      if (controller.signal.aborted) return;
      const message = err instanceof Error ? err.message : "Failed to generate draft.";
      setError(message);
      setMessages([]);
    } finally {
      if (!controller.signal.aborted) setIsLoading(false);
    }
  };

  const handleSend = async () => {
    await generateDraft(input);
  };

  const handleCopy = async (content: string, id: string) => {
    await navigator.clipboard.writeText(content);
    setCopiedId(id);
    window.setTimeout(() => setCopiedId(null), 2000);
  };

  const handleInsert = (content: string) => {
    onInsert?.(content);
    handleOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-full brand-gradient flex items-center justify-center">
              <Sparkles className="w-4 h-4 text-primary-foreground" aria-hidden />
            </div>
            Draft with AI
          </DialogTitle>
          <DialogDescription>
            This tool uses only what you enter here. It does not read this conversation.
          </DialogDescription>
        </DialogHeader>

        <ScrollArea className="flex-1 pr-4" ref={scrollRef}>
          <div className="space-y-4 py-4">
            {messages.length === 0 && !isLoading && !error && (
              <div className="text-center py-8">
                <Sparkles className="w-12 h-12 mx-auto text-muted-foreground/50 mb-3" aria-hidden />
                <p className="text-muted-foreground text-sm">
                  Describe the message you want to write. Nothing from this chat is sent.
                </p>
              </div>
            )}

            <AnimatePresence mode="popLayout">
              {messages.map((msg) => (
                <motion.div
                  key={msg.id}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}
                >
                  <div
                    className={`max-w-[85%] px-4 py-3 rounded-2xl ${
                      msg.role === "user"
                        ? "brand-gradient text-primary-foreground rounded-tr-sm"
                        : "bg-muted rounded-tl-sm"
                    }`}
                  >
                    <p className="text-sm whitespace-pre-wrap">{msg.content}</p>
                    {msg.role === "assistant" && (
                      <div className="flex gap-2 mt-2 pt-2 border-t border-border/50">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 text-xs"
                          onClick={() => void handleCopy(msg.content, msg.id)}
                        >
                          {copiedId === msg.id ? (
                            <Check className="w-3 h-3 mr-1" aria-hidden />
                          ) : (
                            <Copy className="w-3 h-3 mr-1" aria-hidden />
                          )}
                          Copy draft
                        </Button>
                        {onInsert && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-7 text-xs"
                            onClick={() => handleInsert(msg.content)}
                          >
                            <Send className="w-3 h-3 mr-1" aria-hidden />
                            Insert draft
                          </Button>
                        )}
                      </div>
                    )}
                  </div>
                </motion.div>
              ))}
            </AnimatePresence>

            {isLoading && (
              <div className="flex justify-start" role="status" aria-live="polite">
                <div className="bg-muted px-4 py-3 rounded-2xl rounded-tl-sm">
                  <Loader2 className="w-4 h-4 animate-spin" aria-hidden />
                  <span className="sr-only">Generating draft</span>
                </div>
              </div>
            )}

            {error && (
              <div
                className="flex items-start gap-2 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-sm"
                role="alert"
              >
                <AlertCircle className="w-4 h-4 text-destructive shrink-0 mt-0.5" aria-hidden />
                <div className="flex-1">
                  <p className="text-destructive">{error}</p>
                  <Button
                    size="sm"
                    variant="outline"
                    className="mt-2"
                    onClick={() => {
                      if (lastPrompt) void generateDraft(lastPrompt);
                    }}
                  >
                    Retry
                  </Button>
                </div>
              </div>
            )}
          </div>
        </ScrollArea>

        <div className="flex gap-2 pt-4 border-t">
          <Input
            placeholder="Describe the message you want to write"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                void handleSend();
              }
            }}
            disabled={isLoading}
            aria-label="Describe the message you want to write"
          />
          <Button
            onClick={() => void handleSend()}
            disabled={!input.trim() || isLoading}
            className="brand-gradient"
            aria-label="Generate draft"
          >
            {isLoading ? (
              <Loader2 className="w-4 h-4 animate-spin" aria-hidden />
            ) : (
              <Send className="w-4 h-4" aria-hidden />
            )}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
};

/** @deprecated Use DraftWithAIDialog */
export const AskAIDialog = DraftWithAIDialog;
