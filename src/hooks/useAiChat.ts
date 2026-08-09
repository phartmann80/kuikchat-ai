import { useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";

export type ChatRole = "user" | "assistant" | "system";

export interface ChatMessage {
  role: ChatRole;
  content: string;
}

export interface GatewayRequest {
  operation: "chat";
  conversation_id?: string;
  messages: ChatMessage[];
  metadata?: {
    language?: string;
  };
}

export interface GatewayResponse {
  request_id: string;
  conversation_id: string;
  message: ChatMessage;
  provider: string;
  usage: {
    input: number | null;
    output: number | null;
  };
}

export type UseAiChatReturn = {
  messages: ChatMessage[];
  conversationId: string | null;
  isLoading: boolean;
  error: string | null;
  sendMessage: (content: string) => Promise<void>;
  startNewChat: () => void;
  loadConversation: (id: string) => Promise<void>;
};

export const useAiChat = (): UseAiChatReturn => {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const sendMessage = useCallback(async (content: string) => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      setError("Authentication required to use AI assistant.");
      return;
    }

    const userMsg: ChatMessage = { role: "user", content };
    
    // Optimistic UI Update
    setMessages((prev) => [...prev, userMsg]);
    setIsLoading(true);
    setError(null);

    try {
      const payload: GatewayRequest = {
        operation: "chat",
        conversation_id: conversationId || undefined,
        messages: [...messages, userMsg],
        metadata: {
          language: (session.user as any).options?.language || undefined,
        },
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
        }
      );

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error?.message || "Failed to reach AI gateway.");
      }

      const data: GatewayResponse = await response.json();

      if (data.conversation_id && data.conversation_id !== conversationId) {
        setConversationId(data.conversation_id);
      }

      const assistantMsg: ChatMessage = {
        role: "assistant",
        content: data.message.content,
      };

      setMessages((prev) => [...prev, assistantMsg]);
    } catch (err: any) {
      setError(err.message || "An unexpected error occurred.");
      setMessages((prev) => prev.slice(0, -1));
    } finally {
      setIsLoading(false);
    }
  }, [messages, conversationId]);

  const startNewChat = useCallback(() => {
    setMessages([]);
    setConversationId(null);
    setError(null);
  }, []);

  const loadConversation = useCallback(async (id: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const { data, error: fetchError } = await supabase
        .from("ai_messages")
        .select("role, content")
        .eq("conversation_id", id)
        .order("created_at", { ascending: true });

      if (fetchError) throw fetchError;

      const history: ChatMessage[] = (data || []).map((row) => ({
        role: row.role as ChatRole,
        content: row.content,
      }));
      setMessages(history);
      setConversationId(id);
    } catch (err: any) {
      setError(err.message || "Failed to load conversation history.");
    } finally {
      setIsLoading(false);
    }
  }, []);

  return {
    messages,
    conversationId,
    isLoading,
    error,
    sendMessage,
    startNewChat,
    loadConversation,
  };
};
