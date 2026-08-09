import { useState } from "react";
import { Search, Plus, Loader2, UserPlus } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { useUsers, UserProfile } from "@/hooks/useUsers";
import { useChat } from "@/hooks/useChat";
import type { ChatContact } from "./ChatWindow";

interface ContactListProps {
  contacts: ChatContact[];
  selectedContact: ChatContact | null;
  onSelectContact: (contact: ChatContact) => void;
  loading?: boolean;
}

const getInitials = (name: string) =>
  name
    .split(" ")
    .map((part) => part[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

export const ContactList = ({ contacts, selectedContact, onSelectContact, loading }: ContactListProps) => {
  const [searchQuery, setSearchQuery] = useState("");
  const [newChatOpen, setNewChatOpen] = useState(false);
  const [newChatSearch, setNewChatSearch] = useState("");
  const { getOrCreateChat, isResolving } = useChat();
  const { users: allUsers, loading: usersLoading } = useUsers();

  const filteredContacts = contacts.filter((contact) =>
    contact.name.toLowerCase().includes(searchQuery.toLowerCase()),
  );

  const availableUsers = allUsers.filter((user) =>
    (user.display_name || "Unknown User").toLowerCase().includes(newChatSearch.toLowerCase()),
  );

  const buildContact = (profile: UserProfile, chatId: string): ChatContact => {
    const name = profile.display_name || "Unknown User";
    return {
      id: chatId,
      chat_id: chatId,
      user_id: profile.id,
      name,
      avatar: getInitials(name) || "U",
      avatar_url: profile.avatar_url,
      online: false,
      verified: undefined,
      time: "",
      lastMessage: "",
      unread: 0,
      about: profile.bio || "Hey there! I'm using KuikChat",
    };
  };

  const resolveAndSelectContact = async (contact: ChatContact) => {
    const chatId = contact.chat_id || await getOrCreateChat(contact.user_id);
    if (!chatId) return;
    onSelectContact({ ...contact, id: chatId, chat_id: chatId });
  };

  const handleStartChat = async (profile: UserProfile) => {
    const chatId = await getOrCreateChat(profile.id);
    if (!chatId) return;

    setNewChatOpen(false);
    onSelectContact(buildContact(profile, chatId));
  };

  return (
    <div className="flex h-full flex-col bg-[#10202a] text-slate-100">
      <div className="space-y-4 border-b border-slate-800/80 p-4 bg-[#10202a]">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-semibold">Chats</h1>
            <p className="text-xs text-slate-400">Secure business messaging</p>
          </div>
          <Dialog open={newChatOpen} onOpenChange={setNewChatOpen}>
            <DialogTrigger asChild>
              <Button size="icon" className="rounded-full brand-gradient text-primary-foreground">
                <Plus className="h-5 w-5" />
              </Button>
            </DialogTrigger>
            <DialogContent className="border-slate-800 bg-[#10202a] text-slate-100 sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Start a direct chat</DialogTitle>
              </DialogHeader>
              <div className="space-y-4">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
                  <Input
                    value={newChatSearch}
                    onChange={(event) => setNewChatSearch(event.target.value)}
                    placeholder="Search people"
                    className="border-slate-800 bg-[#0b151c] pl-9 text-slate-100 placeholder:text-slate-500 focus-visible:ring-blue-500"
                  />
                </div>
                <div className="max-h-80 space-y-2 overflow-y-auto pr-1">
                  {usersLoading ? (
                    <div className="flex items-center justify-center py-8 text-slate-400">
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Loading people...
                    </div>
                  ) : availableUsers.length === 0 ? (
                    <div className="rounded-xl border border-dashed border-slate-800 p-6 text-center text-sm text-slate-400">
                      <UserPlus className="mx-auto mb-2 h-6 w-6" />
                      No matching users found.
                    </div>
                  ) : (
                    availableUsers.map((profile) => {
                      const name = profile.display_name || "Unknown User";
                      return (
                        <button
                          key={profile.id}
                          type="button"
                          onClick={() => handleStartChat(profile)}
                          disabled={isResolving}
                          className="flex w-full items-center gap-3 rounded-xl p-3 text-left text-slate-100 transition-colors hover:bg-slate-800/70 disabled:opacity-60"
                        >
                          <Avatar className="h-10 w-10">
                            <AvatarImage src={profile.avatar_url || undefined} />
                            <AvatarFallback>{getInitials(name) || "U"}</AvatarFallback>
                          </Avatar>
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-medium">{name}</p>
                            <p className="truncate text-xs text-slate-400">
                              {profile.bio || "Hey there! I'm using KuikChat"}
                            </p>
                          </div>
                        </button>
                      );
                    })
                  )}
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
          <Input
            value={searchQuery}
            onChange={(event) => setSearchQuery(event.target.value)}
            placeholder="Search chats"
            className="border-slate-800 bg-[#0b151c] pl-9 text-slate-100 placeholder:text-slate-500 focus-visible:ring-blue-500"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-2">
        {loading ? (
          <div className="flex items-center justify-center py-10 text-slate-400">
            <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Loading chats...
          </div>
        ) : filteredContacts.length === 0 ? (
          <div className="m-4 rounded-2xl border border-dashed border-slate-800 p-6 text-center text-sm text-slate-400">
            No chats yet. Tap + to start a conversation.
          </div>
        ) : (
          filteredContacts.map((contact) => (
            <button
              key={`${contact.chat_id || "pending"}-${contact.user_id}`}
              type="button"
              onClick={() => resolveAndSelectContact(contact)}
              className={`flex w-full items-center gap-3 rounded-2xl p-3 text-left text-slate-100 transition-colors ${
                selectedContact?.chat_id === contact.chat_id && selectedContact?.user_id === contact.user_id
                  ? "bg-blue-500/15 ring-1 ring-blue-500/30"
                  : "hover:bg-slate-800/70"
              }`}
            >
              <Avatar className="h-12 w-12">
                <AvatarImage src={contact.avatar_url || undefined} />
                <AvatarFallback>{contact.avatar || getInitials(contact.name) || "U"}</AvatarFallback>
              </Avatar>
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <p className="truncate font-medium">{contact.name}</p>
                  <span className="shrink-0 text-[11px] text-slate-500">{contact.time}</span>
                </div>
                <p className="truncate text-sm text-slate-400">{contact.lastMessage || contact.about}</p>
              </div>
              {contact.unread > 0 && (
                <span className="rounded-full bg-primary px-2 py-0.5 text-xs text-primary-foreground">
                  {contact.unread}
                </span>
              )}
            </button>
          ))
        )}
      </div>
    </div>
  );
};
