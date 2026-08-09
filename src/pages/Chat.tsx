import { useEffect, useState } from "react";
import { SidebarProvider } from "@/components/ui/sidebar";
import { ChatSidebar, SidebarView } from "@/components/chat/ChatSidebar";
import { ContactList } from "@/components/chat/ContactList";
import { ChatWindow, ChatContact } from "@/components/chat/ChatWindow";
import { StatusView } from "@/components/chat/StatusView";
import { CommunitiesView } from "@/components/chat/CommunitiesView";
import { VanishModeView } from "@/components/chat/VanishModeView";
import { SettingsView } from "@/components/chat/SettingsView";
import { HiddenChatsVault } from "@/components/chat/HiddenChatsVault";
import { BusinessToolsHub } from "@/components/business/BusinessToolsHub";
import { CallsView } from "@/components/chat/CallsView";
import { ChatInterface } from "@/components/chat/ChatInterface";
import { useUsers } from "@/hooks/useUsers";
import logo from "@/assets/kuikchat-logo.png";

const Chat = () => {
  const [selectedContact, setSelectedContact] = useState<ChatContact | null>(null);
  const [isMobileContactsOpen, setIsMobileContactsOpen] = useState(true);
  const [activeView, setActiveView] = useState<SidebarView>("Chats");
  const [chatWallpaper, setChatWallpaper] = useState<string>("transparent");
  const { users, loading } = useUsers();

  useEffect(() => {
    document.documentElement.classList.add("dark", "business-dark");
    return () => {
      document.documentElement.classList.remove("business-dark");
    };
  }, []);

  const contacts: ChatContact[] = users.map((u) => {
    const name = u.display_name || "Unknown User";
    return {
      id: u.id,
      user_id: u.id,
      name,
      avatar: name.charAt(0).toUpperCase(),
      avatar_url: u.avatar_url,
      lastMessage: "Tap to start chatting",
      time: "",
      unread: 0,
      online: false,
      about: u.bio || "Hey there! I'm using KuikChat",
    };
  });

  const handleSelectContact = (contact: ChatContact) => {
    setSelectedContact(contact);
    setIsMobileContactsOpen(false);
    setActiveView("Chats");
  };

  const renderContent = () => {
    if (activeView === "Hermes AI") {
      return <ChatInterface />;
    }

    switch (activeView) {
      case "Status":
        return <StatusView />;
      case "Calls":
        return <CallsView onStartCall={() => setActiveView("Chats")} />;
      case "Communities":
        return <CommunitiesView />;
      case "Vanish Mode":
        return <VanishModeView />;
      case "Settings":
        return <SettingsView onViewChange={setActiveView} />;
      case "Hidden":
        return <HiddenChatsVault />;
      case "Business":
        return <BusinessToolsHub />;
      case "Chats":
      default:
        return (
          <div className="flex h-full min-h-0 w-full flex-1">
            <div className={`${isMobileContactsOpen ? 'flex' : 'hidden'} md:flex w-full md:w-80 lg:w-96 flex-col min-h-0 border-r border-slate-800/80 bg-[#10202a] text-slate-100`}>
              <ContactList
                contacts={contacts}
                selectedContact={selectedContact}
                onSelectContact={handleSelectContact}
                loading={loading}
              />
            </div>
            <div className={`${!isMobileContactsOpen ? 'flex' : 'hidden'} md:flex flex-1 flex-col min-h-0`}>
              {selectedContact ? (
                <ChatWindow
                  contact={selectedContact}
                  chatId={selectedContact.chat_id ?? null}
                  onBack={() => setIsMobileContactsOpen(true)}
                  wallpaper={chatWallpaper}
                  onWallpaperChange={setChatWallpaper}
                />
              ) : (
                <div className="flex-1 flex items-center justify-center bg-[#0b151c] text-slate-100">
                  <div className="text-center">
                    <div className="w-40 h-40 rounded-full brand-gradient mx-auto mb-4 flex items-center justify-center p-6">
                      <img src={logo} alt="KuikChat" className="w-full h-full object-contain" />
                    </div>
                    <h2 className="text-xl font-semibold mb-2">Welcome to KuikChat</h2>
                    <p className="text-slate-400">Select a conversation to start chatting</p>
                  </div>
                </div>
              )}
            </div>
          </div>
        );
    }
  };

  return (
    <SidebarProvider>
      <div className="dark business-dark flex h-screen w-full overflow-hidden bg-[#0b151c] text-slate-100">
        <ChatSidebar activeView={activeView} onViewChange={setActiveView} />
        <main className="flex-1 flex flex-col min-h-0 relative overflow-hidden">
          {renderContent()}
        </main>
      </div>
    </SidebarProvider>
  );
};

export default Chat;
