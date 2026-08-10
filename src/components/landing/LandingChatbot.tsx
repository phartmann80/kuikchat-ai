import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MessageCircle, X, Send, Loader2, Sparkles, Minimize2, Maximize2, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useToast } from "@/hooks/use-toast";
import { useAiChat } from "@/hooks/useAiChat";
import { supabase } from "@/integrations/supabase/client";

interface Message {
    role: "user" | "assistant";
    content: string;
}

export const LandingChatbot = () => {
    const [isOpen, setIsOpen] = useState(false);
    const [isMinimized, setIsMinimized] = useState(false);
    const [input, setInput] = useState("");
    const [session, setSession] = useState<any>(null);
    const scrollRef = useRef<HTMLDivElement>(null);
    const {
        messages: aiMessages,
        isLoading: aiLoading,
        sendMessage
    } = useAiChat({ mode: "ephemeral" });

    useEffect(() => {
        const getSession = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            setSession(session);
        };
        getSession();

        const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
            setSession(session);
        });

        return () => subscription.unsubscribe();
    }, []);

    useEffect(() => {
        if (scrollRef.current) {
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
        }
    }, [aiMessages, isOpen, isMinimized]);

    const handleSend = async () => {
        if (!input.trim() || aiLoading) return;
        await sendMessage(input);
        setInput("");
    };

    const handleSignIn = () => {
        window.location.href = "/auth";
    };

    return (
        <div className="fixed bottom-6 right-6 z-[100] flex flex-col items-end">
            <AnimatePresence>
                {isOpen && (
                    <motion.div
                        initial={{ opacity: 0, scale: 0.9, y: 20 }}
                        animate={{
                            opacity: 1,
                            scale: 1,
                            y: 0,
                            height: isMinimized ? "64px" : "500px",
                            width: "350px"
                        }}
                        exit={{ opacity: 0, scale: 0.9, y: 20 }}
                        className="glass shadow-2xl rounded-2xl overflow-hidden flex flex-col mb-4 border border-white/20"
                    >
                        {/* Header */}
                        <div className="p-4 brand-gradient flex items-center justify-between text-primary-foreground">
                            <div className="flex items-center gap-2">
                                <div className="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center">
                                    <Sparkles className="w-4 h-4" />
                                </div>
                                <div className="flex flex-col">
                                    <h3 className="font-semibold text-sm">KuikChat AI</h3>
                                    {!isMinimized && <p className="text-[10px] opacity-80">Always active</p>}
                                </div>
                            </div>
                            <div className="flex items-center gap-1">
                                <Button
                                    variant="ghost"
                                    size="icon"
                                    className="h-8 w-8 text-primary-foreground hover:bg-white/10"
                                    onClick={() => setIsMinimized(!isMinimized)}
                                >
                                    {isMinimized ? <Maximize2 className="w-4 h-4" /> : <Minimize2 className="w-4 h-4" />}
                                </Button>
                                <Button
                                    variant="ghost"
                                    size="icon"
                                    className="h-8 w-8 text-primary-foreground hover:bg-white/10"
                                    onClick={() => setIsOpen(false)}
                                >
                                    <X className="w-4 h-4" />
                                </Button>
                            </div>
                        </div>

                        {!isMinimized && (
                            <>
                                <ScrollArea className="flex-1 p-4">
                                    <div className="space-y-4">
                                        {!session ? (
                                            <div className="text-center py-8 space-y-4">
                                                <div className="w-12 h-12 mx-auto rounded-full bg-muted flex items-center justify-center">
                                                    <Lock className="w-6 h-6 text-muted-foreground" />
                                                </div>
                                                <div className="space-y-2">
                                                    <p className="text-sm font-medium">Sign in to use KuikChat AI</p>
                                                    <Button onClick={handleSignIn} className="w-full text-xs">
                                                        Sign In
                                                    </Button>
                                                </div>
                                            </div>
                                        ) : (
                                            <>
                                                {aiMessages.map((msg, i) => (
                                                    <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
                                                        <div className={`max-w-[85%] px-3 py-2 rounded-2xl text-sm ${
                                                            msg.role === "user" 
                                                            ? "brand-gradient text-primary-foreground rounded-tr-none" 
                                                            : "bg-muted rounded-tl-none"
                                                        }`}>
                                                            {msg.content}
                                                        </div>
                                                    </div>
                                                ))}
                                                {aiLoading && (
                                                    <div className="flex justify-start">
                                                        <div className="bg-muted px-3 py-2 rounded-2xl rounded-tl-none">
                                                            <Loader2 className="w-4 h-4 animate-spin text-primary" />
                                                        </div>
                                                    </div>
                                                )}
                                            </>
                                        )}
                                    </div>
                                </ScrollArea>

                                {session && (
                                    <div className="p-3 border-t border-border bg-background/50 backdrop-blur-md">
                                        <div className="flex gap-2">
                                            <Input
                                                placeholder="Type a message..."
                                                value={input}
                                                onChange={(e) => setInput(e.target.value)}
                                                onKeyDown={(e) => e.key === "Enter" && handleSend()}
                                                className="bg-muted/50 border-none h-9 text-sm"
                                                disabled={aiLoading}
                                            />
                                            <Button
                                                size="icon"
                                                onClick={handleSend}
                                                disabled={!input.trim() || aiLoading}
                                                className="h-9 w-9 brand-gradient shrink-0"
                                            >
                                                <Send className="w-4 h-4" />
                                            </Button>
                                        </div>
                                    </div>
                                )}
                            </>
                        )}
                    </motion.div>
                )}
            </AnimatePresence>

            <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                onClick={() => {
                    setIsOpen(true);
                    setIsMinimized(false);
                }}
                className={`w-14 h-14 rounded-full brand-gradient shadow-lg flex items-center justify-center text-primary-foreground transition-transform ${isOpen ? 'scale-0' : 'scale-100'}`}
            >
                <MessageCircle className="w-7 h-7" />
            </motion.button>
        </div>
    );
};
