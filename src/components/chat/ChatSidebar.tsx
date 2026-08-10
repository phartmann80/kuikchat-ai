import { Sparkles, MessageCircle, Users, Phone, Store, EyeOff, LogOut, CircleDot } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useAuth } from "@/contexts/AuthContext";

export type SidebarView = "Chats" | "Status" | "Calls" | "Communities" | "Vanish Mode" | "Settings" | "Hidden" | "Business" | "Hermes AI";

const navItems: { icon: typeof MessageCircle; label: SidebarView }[] = [
  { icon: MessageCircle, label: "Chats" },
  { icon: Sparkles, label: "Hermes AI" },
  { icon: CircleDot, label: "Status" },
  { icon: Phone, label: "Calls" },
  { icon: Users, label: "Communities" },
  { icon: Store, label: "Business" },
  { icon: EyeOff, label: "Vanish Mode" },
];

/**
 * App navigation only. Hermes conversation history lives in ChatInterface
 * (single useAiChat instance) to avoid a disconnected second hook instance.
 */
export const ChatSidebar = ({ activeView, onViewChange }: { activeView: SidebarView, onViewChange: (v: SidebarView) => void }) => {
  const { signOut } = useAuth();

  return (
    <aside className="hidden md:flex w-72 h-full bg-card border-r border-border flex-col">
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div className="flex items-center gap-2 font-bold text-lg">
          <Sparkles className="w-5 h-5 text-primary" />
          <span>KuikChat</span>
        </div>
      </div>

      <div className="flex-1" />

      <div className="p-4 border-t border-border space-y-1">
        {navItems.map((item) => (
          <button
            key={item.label}
            type="button"
            onClick={() => onViewChange(item.label)}
            className={cn(
              "w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors",
              activeView === item.label ? "bg-primary/10 text-primary" : "hover:bg-muted text-muted-foreground"
            )}
          >
            <item.icon className="w-4 h-4" />
            {item.label}
          </button>
        ))}
        <Button variant="ghost" className="w-full justify-start gap-3 text-destructive hover:text-destructive hover:bg-destructive/10" onClick={() => signOut()}>
          <LogOut className="w-4 h-4" /> Logout
        </Button>
      </div>
    </aside>
  );
};
