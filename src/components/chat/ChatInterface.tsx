import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Send,
  Loader2,
  MessageSquare,
  Plus,
  MoreVertical,
  Sparkles,
  AlertCircle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";
import { useAiChat } from "@/hooks/useAiChat";
import { format } from "date-fns";
import { shouldShowNewChatHero } from "@/lib/hermesConversationSelection";

export const ChatInterface = () => {
  const {
    messages,
    conversationId,
    conversations,
    historyStatus,
    historyError,
    isLoading,
    error,
    sendMessage,
    startNewChat,
    loadConversation,
    retryHistory,
  } = useAiChat({ mode: "hermes" });

  const [input, setInput] = useState("");
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isLoading]);

  const handleSend = async () => {
    if (!input.trim() || isLoading) return;
    const content = input;
    setInput("");
    await sendMessage(content);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void handleSend();
    }
  };

  const showHero =
    messages.length === 0 &&
    shouldShowNewChatHero({
      conversationsLoaded: historyStatus === "ready" || historyStatus === "empty",
      conversationCount: conversations.length,
      selectedId: conversationId,
      forceNewChat: !conversationId && (historyStatus === "ready" || historyStatus === "empty"),
    });

  const historyPanel = (
    <>
      {historyStatus === "loading" && (
        <div className="px-2 py-4 text-xs text-muted-foreground italic flex items-center gap-2">
          <Loader2 className="w-3 h-3 animate-spin" />
          Loading history…
        </div>
      )}
      {historyStatus === "error" && (
        <div className="px-2 py-3 space-y-2">
          <p className="text-xs text-destructive">{historyError || "Failed to load history."}</p>
          <Button size="sm" variant="outline" className="w-full" onClick={() => void retryHistory()}>
            Retry
          </Button>
        </div>
      )}
      {historyStatus === "empty" && (
        <div className="px-2 py-4 text-xs text-muted-foreground text-center">
          No conversations yet. Start a new chat.
        </div>
      )}
      {(historyStatus === "ready" || historyStatus === "empty") &&
        conversations.map((conv) => (
          <button
            key={conv.id}
            type="button"
            onClick={() => void loadConversation(conv.id)}
            className={cn(
              "w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors",
              conversationId === conv.id
                ? "bg-primary/10 text-primary"
                : "hover:bg-muted text-muted-foreground",
            )}
          >
            <MessageSquare className="w-4 h-4 shrink-0" />
            <div className="flex flex-col items-start overflow-hidden">
              <span className="truncate w-full text-left">{conv.title || "Untitled Chat"}</span>
              <span className="text-[10px] opacity-60">
                {format(new Date(conv.updated_at), "MMM d, h:mm a")}
              </span>
            </div>
          </button>
        ))}
    </>
  );

  return (
    <div className="flex h-full w-full bg-background text-foreground overflow-hidden">
      <aside
        className={cn(
          "hidden md:flex flex-col w-72 border-r border-border bg-card/50 backdrop-blur-xl transition-all duration-300",
          !isSidebarOpen && "w-0 opacity-0 overflow-hidden",
        )}
      >
        <div className="p-4 flex items-center justify-between">
          <div className="flex items-center gap-2 font-bold text-lg">
            <div className="w-8 h-8 rounded-lg brand-gradient flex items-center justify-center">
              <Sparkles className="w-5 h-5 text-primary-foreground" />
            </div>
            <span>Hermes AI</span>
          </div>
          <Button variant="ghost" size="icon" onClick={() => setIsSidebarOpen(false)}>
            <MoreVertical className="w-4 h-4" />
          </Button>
        </div>

        <div className="px-3 mb-4">
          <Button
            onClick={startNewChat}
            className="w-full justify-start gap-2 brand-gradient text-primary-foreground"
          >
            <Plus className="w-4 h-4" />
            New Chat
          </Button>
        </div>

        <ScrollArea className="flex-1 px-3">
          <div className="space-y-1">
            <div className="text-xs font-medium text-muted-foreground px-2 py-2 uppercase tracking-wider">
              Recent Chats
            </div>
            {historyPanel}
          </div>
        </ScrollArea>
      </aside>

      <main className="flex-1 flex flex-col relative min-w-0">
        <header className="md:hidden p-4 border-b flex items-center justify-between bg-background/80 backdrop-blur-md z-10">
          <div className="flex items-center gap-2 font-bold">
            <Sparkles className="w-5 h-5 text-primary" />
            <span>Hermes AI</span>
          </div>
          <Button variant="ghost" size="icon" onClick={() => setIsSidebarOpen(true)}>
            <MessageSquare className="w-5 h-5" />
          </Button>
        </header>

        {/* Mobile history drawer */}
        {isSidebarOpen && (
          <div className="md:hidden absolute inset-0 z-20 bg-background/95 backdrop-blur-md flex flex-col">
            <div className="p-4 flex items-center justify-between border-b">
              <span className="font-semibold">Conversations</span>
              <Button variant="ghost" size="sm" onClick={() => setIsSidebarOpen(false)}>
                Close
              </Button>
            </div>
            <div className="p-3">
              <Button
                onClick={() => {
                  startNewChat();
                  setIsSidebarOpen(false);
                }}
                className="w-full justify-start gap-2 brand-gradient text-primary-foreground mb-3"
              >
                <Plus className="w-4 h-4" />
                New Chat
              </Button>
            </div>
            <ScrollArea className="flex-1 px-3">{historyPanel}</ScrollArea>
          </div>
        )}

        <ScrollArea className="flex-1" ref={scrollRef}>
          <div className="max-w-3xl mx-auto w-full px-4 py-8">
            {historyStatus === "loading" && messages.length === 0 && (
              <div className="flex flex-col items-center justify-center min-h-[40vh] text-muted-foreground gap-3">
                <Loader2 className="w-6 h-6 animate-spin" />
                <p className="text-sm">Loading conversation…</p>
              </div>
            )}

            {historyStatus === "error" && messages.length === 0 && (
              <div className="flex flex-col items-center justify-center min-h-[40vh] text-center gap-4">
                <AlertCircle className="w-10 h-10 text-destructive" />
                <p className="text-sm text-muted-foreground">{historyError}</p>
                <Button variant="outline" onClick={() => void retryHistory()}>
                  Retry
                </Button>
              </div>
            )}

            <AnimatePresence mode="popLayout">
              {showHero && historyStatus !== "loading" && historyStatus !== "error" ? (
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="flex flex-col items-center justify-center min-h-[60vh] text-center space-y-6"
                >
                  <div className="w-16 h-16 rounded-2xl brand-gradient flex items-center justify-center shadow-lg shadow-primary/20">
                    <Sparkles className="w-8 h-8 text-primary-foreground" />
                  </div>
                  <div className="space-y-2">
                    <h2 className="text-2xl font-bold">How can I help you today?</h2>
                    <p className="text-muted-foreground max-w-xs">
                      Ask me anything about your business, code, or brainstorm new ideas.
                    </p>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 w-full max-w-md">
                    {["Summarize my docs", "Draft a reply", "Write some code", "Brainstorm ideas"].map(
                      (suggestion) => (
                        <Button
                          key={suggestion}
                          variant="secondary"
                          className="justify-start text-left font-normal h-auto py-3 px-4 text-sm"
                          onClick={() => void sendMessage(suggestion)}
                        >
                          {suggestion}
                        </Button>
                      ),
                    )}
                  </div>
                </motion.div>
              ) : messages.length > 0 ? (
                <div className="space-y-6" data-testid="hermes-message-list">
                  {messages.map((msg) => (
                    <motion.div
                      key={msg.id}
                      data-testid="hermes-message"
                      data-message-id={msg.id}
                      data-role={msg.role}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}
                    >
                      <div
                        className={cn(
                          "max-w-[85%] px-4 py-3 rounded-2xl text-sm leading-relaxed",
                          msg.role === "user"
                            ? "brand-gradient text-primary-foreground rounded-tr-none"
                            : "bg-muted/50 border border-border/50 rounded-tl-none",
                        )}
                      >
                        {msg.content}
                      </div>
                    </motion.div>
                  ))}
                  {isLoading && (
                    <motion.div
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      className="flex justify-start"
                      data-testid="hermes-typing"
                    >
                      <div className="bg-muted/50 px-4 py-3 rounded-2xl rounded-tl-none border border-border/50">
                        <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
                      </div>
                    </motion.div>
                  )}
                </div>
              ) : null}
            </AnimatePresence>

            {error && (
              <div className="mt-4 flex items-start gap-2 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-sm">
                <AlertCircle className="w-4 h-4 text-destructive shrink-0 mt-0.5" />
                <div className="flex-1">
                  <p className="text-destructive">{error}</p>
                  <Button
                    size="sm"
                    variant="outline"
                    className="mt-2"
                    onClick={() => {
                      if (input.trim()) void sendMessage(input);
                    }}
                  >
                    Retry
                  </Button>
                </div>
              </div>
            )}
          </div>
        </ScrollArea>

        <div className="w-full border-t bg-background/80 backdrop-blur-md p-4">
          <div className="max-w-3xl mx-auto relative">
            <textarea
              rows={1}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Message Hermes AI..."
              className="w-full resize-none rounded-2xl border border-border bg-muted/50 py-3 pl-4 pr-12 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 transition-all min-h-[44px] max-h-[200px]"
            />
            <Button
              size="icon"
              className="absolute right-2 bottom-1.5 h-8 w-8 brand-gradient text-primary-foreground"
              disabled={!input.trim() || isLoading}
              onClick={() => void handleSend()}
            >
              {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            </Button>
          </div>
          <p className="text-[10px] text-center text-muted-foreground mt-2">
            Hermes AI can make mistakes. Check important info.
          </p>
        </div>
      </main>
    </div>
  );
};
