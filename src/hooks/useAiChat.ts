import { useState, useCallback, useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import {
  selectHermesConversationId,
  type HermesConversationSummary,
} from "@/lib/hermesConversationSelection";

export type ChatRole = "user" | "assistant" | "system";

export interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
}

export interface GatewayRequest {
  operation: "chat";
  conversation_id?: string;
  messages: Array<{ role: ChatRole; content: string }>;
  metadata?: {
    language?: string;
  };
}

export interface GatewayResponse {
  request_id: string;
  conversation_id: string;
  message: { role: ChatRole; content: string };
  provider: string;
  usage: {
    input: number | null;
    output: number | null;
  };
}

export type HistoryStatus = "idle" | "loading" | "ready" | "empty" | "error";

export type UseAiChatOptions = {
  /**
   * hermes: load conversation list + restore selected/most-recent on auth mount.
   * ephemeral: no history bootstrap (Ask AI dialog, landing chatbot).
   */
  mode?: "hermes" | "ephemeral";
};

export type UseAiChatReturn = {
  messages: ChatMessage[];
  conversationId: string | null;
  conversations: HermesConversationSummary[];
  historyStatus: HistoryStatus;
  historyError: string | null;
  isLoading: boolean;
  error: string | null;
  sendMessage: (content: string) => Promise<void>;
  startNewChat: () => void;
  loadConversation: (id: string) => Promise<boolean>;
  refreshConversations: () => Promise<void>;
  retryHistory: () => Promise<void>;
};

const STORAGE_KEY = "kuikchat.hermes.selectedConversationId";

const readPreferredId = (): string | null => {
  if (typeof window === "undefined") return null;
  try {
    const fromUrl = new URLSearchParams(window.location.search).get("hermes");
    if (fromUrl && /^[0-9a-f-]{36}$/i.test(fromUrl)) return fromUrl;
    const fromStorage = window.sessionStorage.getItem(STORAGE_KEY);
    if (fromStorage && /^[0-9a-f-]{36}$/i.test(fromStorage)) return fromStorage;
  } catch {
    /* ignore */
  }
  return null;
};

const persistPreferredId = (id: string | null) => {
  if (typeof window === "undefined") return;
  try {
    if (id) window.sessionStorage.setItem(STORAGE_KEY, id);
    else window.sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    /* ignore */
  }
};

export const useAiChat = (options: UseAiChatOptions = {}): UseAiChatReturn => {
  const mode = options.mode ?? "hermes";
  const { user, loading: authLoading } = useAuth();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [conversations, setConversations] = useState<HermesConversationSummary[]>([]);
  const [historyStatus, setHistoryStatus] = useState<HistoryStatus>(
    mode === "hermes" ? "idle" : "ready",
  );
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadSeq = useRef(0);
  const bootstrapSeq = useRef(0);
  const conversationIdRef = useRef<string | null>(null);
  const messagesRef = useRef<ChatMessage[]>([]);
  const abortRef = useRef<AbortController | null>(null);
  const skipNextBootstrapRef = useRef(false);
  const userId = user?.id ?? null;

  useEffect(() => {
    conversationIdRef.current = conversationId;
  }, [conversationId]);

  useEffect(() => {
    messagesRef.current = messages;
  }, [messages]);

  const refreshConversations = useCallback(async () => {
    if (!userId) {
      setConversations([]);
      return;
    }
    const { data, error: listError } = await supabase
      .from("ai_conversations")
      .select("id, title, updated_at")
      .eq("user_id", userId)
      .order("updated_at", { ascending: false });

    if (listError) throw listError;
    setConversations((data || []) as HermesConversationSummary[]);
  }, [userId]);

  const loadConversation = useCallback(async (id: string): Promise<boolean> => {
    if (!userId) {
      setHistoryError("Authentication required.");
      setHistoryStatus("error");
      return false;
    }

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const seq = ++loadSeq.current;

    setIsLoading(true);
    setError(null);
    setHistoryError(null);
    // Drop prior messages immediately so rapid switches never show stale content.
    setMessages([]);
    setConversationId(id);

    try {
      const ownership = await supabase
        .from("ai_conversations")
        .select("id, user_id")
        .eq("id", id)
        .eq("user_id", userId)
        .maybeSingle();

      if (controller.signal.aborted || seq !== loadSeq.current) return false;

      if (ownership.error) throw ownership.error;
      if (!ownership.data) {
        setHistoryError("Conversation not found or access denied.");
        setHistoryStatus("error");
        setMessages([]);
        setConversationId(null);
        persistPreferredId(null);
        return false;
      }

      const { data, error: fetchError } = await supabase
        .from("ai_messages")
        .select("id, role, content")
        .eq("conversation_id", id)
        .order("created_at", { ascending: true });

      if (controller.signal.aborted || seq !== loadSeq.current) return false;
      if (fetchError) throw fetchError;

      const history: ChatMessage[] = (data || []).map((row) => ({
        id: row.id,
        role: row.role as ChatRole,
        content: row.content,
      }));

      setMessages(history);
      setConversationId(id);
      persistPreferredId(id);
      setHistoryStatus("ready");
      return true;
    } catch (err: unknown) {
      if (controller.signal.aborted || seq !== loadSeq.current) return false;
      const message = err instanceof Error ? err.message : "Failed to load conversation history.";
      setHistoryError(message);
      setHistoryStatus("error");
      setMessages([]);
      setConversationId(null);
      return false;
    } finally {
      if (seq === loadSeq.current) setIsLoading(false);
    }
  }, [userId]);

  const bootstrap = useCallback(async () => {
    if (mode !== "hermes") return;
    if (authLoading) return;

    if (!userId) {
      setConversations([]);
      setMessages([]);
      setConversationId(null);
      setHistoryStatus("idle");
      return;
    }

    if (skipNextBootstrapRef.current) {
      skipNextBootstrapRef.current = false;
      return;
    }

    const seq = ++bootstrapSeq.current;
    setHistoryStatus("loading");
    setHistoryError(null);

    try {
      const { data, error: listError } = await supabase
        .from("ai_conversations")
        .select("id, title, updated_at")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false });

      if (seq !== bootstrapSeq.current) return;
      if (listError) throw listError;

      const list = (data || []) as HermesConversationSummary[];
      setConversations(list);

      if (!list.length) {
        setMessages([]);
        setConversationId(null);
        persistPreferredId(null);
        setHistoryStatus("empty");
        return;
      }

      const preferred = readPreferredId();
      const selected = selectHermesConversationId({
        preferredId: preferred,
        conversations: list,
      });

      if (!selected) {
        setHistoryStatus("empty");
        return;
      }

      const ok = await loadConversation(selected);
      if (seq !== bootstrapSeq.current) return;

      if (!ok && preferred && list[0] && list[0].id !== preferred) {
        await loadConversation(list[0].id);
      }

      if (seq === bootstrapSeq.current) {
        setHistoryStatus((prev) => (prev === "error" ? "error" : "ready"));
      }
    } catch (err: unknown) {
      if (seq !== bootstrapSeq.current) return;
      const message = err instanceof Error ? err.message : "Failed to load conversations.";
      setHistoryError(message);
      setHistoryStatus("error");
    }
  }, [mode, authLoading, userId, loadConversation]);

  useEffect(() => {
    void bootstrap();
    return () => {
      abortRef.current?.abort();
      bootstrapSeq.current += 1;
      loadSeq.current += 1;
    };
  }, [bootstrap]);

  const startNewChat = useCallback(() => {
    abortRef.current?.abort();
    loadSeq.current += 1;
    if (mode === "hermes") {
      // Avoid immediately re-bootstrapping into the previous conversation.
      skipNextBootstrapRef.current = true;
    }
    setMessages([]);
    setConversationId(null);
    setError(null);
    setHistoryError(null);
    persistPreferredId(null);
    setHistoryStatus(conversations.length ? "ready" : mode === "hermes" ? "empty" : "ready");
  }, [conversations.length, mode]);

  const sendMessage = useCallback(async (content: string) => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      setError("Authentication required to use AI assistant.");
      return;
    }

    const optimisticId = `local-user-${crypto.randomUUID()}`;
    const userMsg: ChatMessage = { id: optimisticId, role: "user", content };
    const prior = messagesRef.current;
    const activeConversationId = conversationIdRef.current;

    setMessages((prev) => [...prev, userMsg]);
    setIsLoading(true);
    setError(null);

    try {
      const payload: GatewayRequest = {
        operation: "chat",
        conversation_id: activeConversationId || undefined,
        messages: [...prior, { role: "user", content }].map(({ role, content: text }) => ({
          role,
          content: text,
        })),
      };

      const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/ai-gateway`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${session.access_token}`,
          },
          body: JSON.stringify(payload),
        },
      );

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.error?.message || "Failed to reach AI gateway.");
      }

      const data: GatewayResponse = await response.json();

      if (data.conversation_id) {
        setConversationId(data.conversation_id);
        conversationIdRef.current = data.conversation_id;
        if (mode === "hermes") persistPreferredId(data.conversation_id);
      }

      const assistantMsg: ChatMessage = {
        id: `local-assistant-${data.request_id || crypto.randomUUID()}`,
        role: "assistant",
        content: data.message.content,
      };

      setMessages((prev) => {
        if (prev.some((m) => m.id === assistantMsg.id)) return prev;
        return [...prev, assistantMsg];
      });

      if (mode === "hermes") {
        await refreshConversations().catch(() => undefined);
        setHistoryStatus("ready");
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "An unexpected error occurred.";
      setError(message);
      setMessages((prev) => prev.filter((m) => m.id !== optimisticId));
    } finally {
      setIsLoading(false);
    }
  }, [mode, refreshConversations]);

  const retryHistory = useCallback(async () => {
    skipNextBootstrapRef.current = false;
    await bootstrap();
  }, [bootstrap]);

  return {
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
    refreshConversations,
    retryHistory,
  };
};
