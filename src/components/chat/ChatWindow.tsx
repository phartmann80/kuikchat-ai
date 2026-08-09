import { useState, useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { 
  ArrowLeft, 
  Phone, 
  Video, 
  MoreVertical, 
  Smile, 
  Paperclip, 
  Mic, 
  Send,
  Sparkles,
  Image as ImageIcon,
  FileText,
  Camera,
  MapPin,
  Calendar,
  Languages,
  Loader2,
  Scan,
  QrCode,
  Timer,
  Palette,
  Bot,
  PhoneCall,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import { useMessages } from "@/hooks/useMessages";
import { useAuth } from "@/contexts/AuthContext";
import { useTranslation, SupportedLanguage } from "@/hooks/useTranslation";
import { VoiceRecorder, VoiceNotePlayer } from "./VoiceRecorder";
import { WallpaperPicker } from "./WallpaperPicker";
import { VideoCallModal } from "./VideoCallModal";
import { EventCreator, CalendarEvent } from "./EventCreator";
import { DocumentScanner } from "./DocumentScanner";
import { QRCodeScanner } from "./QRCodeScanner";
import { VerifiedBadge, VerificationType } from "./VerifiedBadge";
import { EncryptionBanner, EncryptionIndicator } from "./EncryptionBanner";
import { DisappearingMessagesSettings, DisappearingMessageIndicator, DisappearingDuration } from "./DisappearingMessagesSettings";
import { ScreenshotAlert } from "./ScreenshotAlert";
import { MessageContextMenu } from "./MessageContextMenu";
import { ScheduleMessageDialog, RepeatType } from "./ScheduleMessageDialog";
import { ReplyBubble } from "./ReplyBubble";
import { AskAIDialog } from "./AskAIDialog";
import { AIArtStudio } from "./AIArtStudio";
import { MultimodalAICall } from "./MultimodalAICall";
import { useToast } from "@/hooks/use-toast";
import { EmojiPicker } from "./EmojiPicker";
import { cn } from "@/lib/utils";

export interface ChatContact {
  id: string;
  chat_id?: string;
  user_id: string;
  name: string;
  avatar: string;
  avatar_url?: string | null;
  lastMessage: string;
  time: string;
  unread: number;
  online: boolean;
  about: string;
  verified?: VerificationType;
}

interface ChatWindowProps {
  contact: ChatContact;
  chatId?: string | null;
  onBack: () => void;
  wallpaper?: string;
  onWallpaperChange?: (wallpaper: string) => void;
}

const attachmentOptions = [
  { icon: ImageIcon, label: "Photo & Video", color: "from-purple-500 to-pink-500", action: "photo" },
  { icon: Scan, label: "Document Scan", color: "from-primary/80 to-secondary/80", action: "scan" },
  { icon: Calendar, label: "Event", color: "from-orange-500 to-amber-500", action: "event" },
  { icon: MapPin, label: "Location", color: "from-green-500 to-emerald-500", action: "location" },
  { icon: QrCode, label: "QR Code", color: "from-pink-500 to-rose-500", action: "qr" },
  { icon: Palette, label: "AI Art", color: "from-primary to-secondary", action: "ai-art" },
  { icon: Bot, label: "Ask AI", color: "from-violet-500 to-purple-500", action: "ask-ai" },
  { icon: PhoneCall, label: "AI Call", color: "from-cyan-500 to-blue-500", action: "ai-call" },
];

export const ChatWindow = ({ chatId, contact, onBack, wallpaper = "transparent", onWallpaperChange }: ChatWindowProps) => {
  const [messageText, setMessageText] = useState("");
  const [showAttachments, setShowAttachments] = useState(false);
  const [showVoiceRecorder, setShowVoiceRecorder] = useState(false);
  const [translatedMessages, setTranslatedMessages] = useState<Record<string, string>>({});
  const [showVideoCall, setShowVideoCall] = useState(false);
  const [isVideoCall, setIsVideoCall] = useState(true);
  const [showEventCreator, setShowEventCreator] = useState(false);
  const [showDocScanner, setShowDocScanner] = useState(false);
  const [showQRScanner, setShowQRScanner] = useState(false);
  const [events, setEvents] = useState<CalendarEvent[]>([]);
  const [disappearingDuration, setDisappearingDuration] = useState<DisappearingDuration>("off");
  const [showEncryptionBanner, setShowEncryptionBanner] = useState(true);
  const [showScheduleDialog, setShowScheduleDialog] = useState(false);
  const [replyingTo, setReplyingTo] = useState<{ id: string; content: string; sender: string } | null>(null);
  const [showAskAI, setShowAskAI] = useState(false);
  const [showAIArt, setShowAIArt] = useState(false);
  const [showAICall, setShowAICall] = useState(false);
  const [longPressTimer, setLongPressTimer] = useState<NodeJS.Timeout | null>(null);
  const [voiceNotes, setVoiceNotes] = useState<Record<string, { url: string; duration: number }>>({});
  const resolvedChatId = chatId || contact.chat_id || contact.id;
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messageRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const { user } = useAuth();
  const { messages, sendMessage, markAsRead } = useMessages(resolvedChatId);
  const { translateText } = useTranslation();
  const { toast } = useToast();

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, events]);

  useEffect(() => {
    markAsRead();
  }, [resolvedChatId, markAsRead]);

  const handleSend = async () => {
    if (!messageText.trim()) return;
    await sendMessage(messageText);
    setMessageText("");
    setShowAttachments(false);
  };

  const handleVoiceSend = async (audioBlob: Blob, duration: number) => {
    setShowVoiceRecorder(false);
    const audioUrl = URL.createObjectURL(audioBlob);
    const voiceId = `voice-${Date.now()}`;
    
    setVoiceNotes(prev => ({
      ...prev,
      [voiceId]: { url: audioUrl, duration }
    }));
    
    await sendMessage(`[VOICE:${voiceId}:${duration}]`);
  };

  const handleTranslate = async (messageId: string, text: string, targetLanguage: SupportedLanguage) => {
    const translated = await translateText(text, targetLanguage);
    if (translated) {
      setTranslatedMessages(prev => ({ ...prev, [messageId]: translated }));
    }
  };

  const handleVideoCall = () => {
    setIsVideoCall(true);
    setShowVideoCall(true);
  };

  const handleVoiceCall = () => {
    setIsVideoCall(false);
    setShowVideoCall(true);
  };

  const handleSendEvent = async (event: CalendarEvent) => {
    setEvents(prev => [...prev, event]);
    await sendMessage(`📅 Event: ${event.title} on ${event.date}${event.time ? ` at ${event.time}` : ""}${event.location ? ` - ${event.location}` : ""}`);
  };

  const handleScanDocument = async (imageData: string) => {
    await sendMessage(`Scanned document attached`);
  };

  const handleAttachmentAction = async (action: string) => {
    setShowAttachments(false);
    switch (action) {
      case "photo": {
        const photoInput = document.createElement('input');
        photoInput.type = 'file';
        photoInput.accept = 'image/*,video/*';
        photoInput.multiple = true;
        photoInput.onchange = async (e) => {
          const files = (e.target as HTMLInputElement).files;
          if (files && files.length > 0) {
            for (const file of Array.from(files)) {
              const isVideo = file.type.startsWith('video/');
              toast({
                title: isVideo ? "Video attached" : "Photo attached",
                description: `${file.name} ready to send`
              });
              await sendMessage(`${isVideo ? 'Video' : 'Photo'}: ${file.name}`);
            }
          }
        };
        photoInput.click();
        break;
      }
      case "location":
        if ('geolocation' in navigator) {
          toast({ title: "Getting location...", description: "Please allow location access" });
          navigator.geolocation.getCurrentPosition(
            async (position) => {
              const { latitude, longitude } = position.coords;
              const locationUrl = `https://www.google.com/maps?q=${latitude},${longitude}`;
              await sendMessage(`📍 Location: ${locationUrl}`);
              toast({ title: "Location shared", description: "Your location has been sent" });
            },
            (error) => {
              toast({ title: "Location error", description: "Could not get your location. Please enable location services.", variant: "destructive" });
            }
          );
        } else {
          toast({ title: "Not supported", description: "Location is not supported in your browser", variant: "destructive" });
        }
        break;
      case "event":
        setShowEventCreator(true);
        break;
      case "scan":
        setShowDocScanner(true);
        break;
      case "qr":
        setShowQRScanner(true);
        break;
      case "ai-art":
        setShowAIArt(true);
        break;
      case "ask-ai":
        setShowAskAI(true);
        break;
      case "ai-call":
        setShowAICall(true);
        break;
      default:
        break;
    }
  };

  const handleReply = (messageId: string) => {
    const msg = messages.find(m => m.id === messageId);
    if (msg) {
      const senderName = msg.sender_id === user?.id ? "You" : contact.name;
      setReplyingTo({ id: messageId, content: msg.content, sender: senderName });
    }
  };

  const handleScheduleMessage = (scheduledAt: Date, repeatType: RepeatType) => {
    toast({
      title: "Message Scheduled",
      description: `Your message will be sent ${repeatType === "once" ? "on" : "starting"} ${scheduledAt.toLocaleString()}`,
    });
    setMessageText("");
  };

  const handleSendButtonDown = () => {
    const timer = setTimeout(() => {
      if (messageText.trim()) {
        setShowScheduleDialog(true);
      }
    }, 500);
    setLongPressTimer(timer);
  };

  const handleSendButtonUp = () => {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      setLongPressTimer(null);
    }
  };

  const handleAIArtSend = async (imageUrl: string, prompt: string) => {
    await sendMessage(`AI Art: "${prompt}"
${imageUrl}`);
  };

  const formatTime = (dateString: string) => {
    return new Date(dateString).toLocaleTimeString([], { 
      hour: '2-digit', 
      minute: '2-digit' 
    });
  };

  const getWallpaperStyle = () => {
    if (!wallpaper || wallpaper === "transparent") return {};
    if (wallpaper.startsWith("http") || wallpaper.startsWith("data:")) {
      return {
        backgroundImage: `url(${wallpaper})`,
        backgroundSize: "cover",
        backgroundPosition: "center",
      };
    }
    return { backgroundColor: wallpaper };
  };

  return (
    <div className="flex h-full min-h-0 flex-col bg-[#0b151c] text-slate-100">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-slate-800/80 bg-[#10202a] shrink-0">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" className="md:hidden" onClick={onBack}>
            <ArrowLeft className="w-5 h-5" />
          </Button>
          <div className="relative">
            <div className={`w-10 h-10 rounded-full flex items-center justify-center text-primary-foreground font-semibold ${
              contact.id === "ai" ? "brand-gradient" : "bg-muted-foreground/20 text-foreground"
            }`}>
              {contact.avatar_url ? (
                <img src={contact.avatar_url} alt={contact.name} className="w-full h-full rounded-full object-cover" />
              ) : (
                contact.avatar
              )}
            </div>
            {contact.online && (
              <div className="absolute bottom-0 right-0 w-3 h-3 bg-secondary rounded-full border-2 border-card" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-1">
              <h2 className="font-semibold text-slate-100">{contact.name}</h2>
              {contact.verified && <VerifiedBadge type={contact.verified} size="sm" />}
            </div>
            <div className="flex items-center gap-2">
              <p className="text-xs text-slate-400">
                {contact.online ? "Online" : "Last seen recently"}
              </p>
              <EncryptionBanner contactName={contact.name} />
              {disappearingDuration !== "off" && (
                <DisappearingMessageIndicator duration={disappearingDuration} />
              )}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <Button variant="ghost" size="icon" className="rounded-full" onClick={handleVoiceCall}>
            <Phone className="w-5 h-5" />
          </Button>
          <Button variant="ghost" size="icon" className="rounded-full" onClick={handleVideoCall}>
            <Video className="w-5 h-5" />
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="rounded-full">
                <MoreVertical className="w-5 h-5" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {onWallpaperChange && (
                <WallpaperPicker
                  currentWallpaper={wallpaper}
                  onWallpaperChange={onWallpaperChange}
                  trigger={
                    <DropdownMenuItem onSelect={(e) => e.preventDefault()}>
                      <ImageIcon className="w-4 h-4 mr-2" />
                      Change Wallpaper
                    </DropdownMenuItem>
                  }
                />
              )}
              <DropdownMenuSeparator />
              <DisappearingMessagesSettings
                currentDuration={disappearingDuration}
                onDurationChange={setDisappearingDuration}
                trigger={
                  <DropdownMenuItem onSelect={(e) => e.preventDefault()}>
                    <Timer className="w-4 h-4 mr-2" />
                    Disappearing Messages
                  </DropdownMenuItem>
                }
              />
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {/* Encryption Banner */}
      {showEncryptionBanner && (
        <EncryptionBanner contactName={contact.name} />
      )}

      {/* Screenshot Alert */}
      <ScreenshotAlert chatId={resolvedChatId} contactName={contact.name} />

      {/* Messages */}
      <div
        className="flex-1 min-h-0 overflow-y-auto p-4 space-y-4"
        style={getWallpaperStyle()}
      >
        {messages.length === 0 ? (
          <div className="flex h-full items-center justify-center">
            <p className="text-slate-400 bg-slate-900/60 px-4 py-2 rounded-lg">No messages yet. Start the conversation!</p>
          </div>
        ) : (
          messages.map((msg, index) => {
            const isOwnMessage = msg.sender_id === user?.id;
            return (
              <motion.div
                key={msg.id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.02 }}
                className={`flex items-end gap-2 ${isOwnMessage ? "justify-end" : "justify-start"}`}
              >
                {!isOwnMessage && (
                  <div className="w-8 h-8 rounded-full shrink-0 overflow-hidden bg-muted-foreground/20 flex items-center justify-center text-xs font-semibold">
                    {contact.avatar}
                  </div>
                )}
                
                <MessageContextMenu
                  messageId={msg.id}
                  messageContent={msg.content}
                  isOwnMessage={isOwnMessage}
                  onTranslate={(id, content, lang) => handleTranslate(id, content, lang)}
                  onReply={handleReply}
                >
                  <div 
                    ref={el => messageRefs.current[msg.id] = el}
                    className={`max-w-[75%] sm:max-w-[65%] ${
                      isOwnMessage 
                        ? "brand-gradient text-primary-foreground rounded-2xl rounded-tr-none" 
                        : "glass rounded-2xl rounded-tl-none"
                    } px-4 py-3 group relative cursor-pointer transition-all`}
                  >
                    {msg.content.startsWith("[VOICE:") ? (
                      (() => {
                        const match = msg.content.match(/\[VOICE:(voice-\d+):(\d+)\]/);
                        if (match) {
                          const voiceId = match[1];
                          const duration = parseInt(match[2], 10);
                          const voiceNote = voiceNotes[voiceId];
                          
                          return voiceNote ? (
                            <VoiceNotePlayer audioUrl={voiceNote.url} duration={voiceNote.duration} />
                          ) : (
                            <div className="flex items-center gap-2 py-1">
                              <div className={`w-8 h-8 rounded-full flex items-center justify-center ${isOwnMessage ? "bg-primary-foreground/20" : "bg-primary/20"}`}>
                                <Mic className={`w-4 h-4 ${isOwnMessage ? "text-primary-foreground" : "text-primary"}`} />
                              </div>
                              <div className="flex-1">
                                <div className={`h-1 rounded-full ${isOwnMessage ? "bg-primary-foreground/30" : "bg-muted"}`} />
                              </div>
                              <span className={`text-xs font-mono ${isOwnMessage ? "text-primary-foreground/70" : "text-muted-foreground"}`}>
                                {msg.content.match(/\(([^)]+)\)/)?.[1] || "0:00"}
                              </span>
                            </div>
                          );
                        }
                        return <p className="text-sm">{msg.content}</p>;
                      })()
                    ) : (
                      <p className="text-sm whitespace-pre-wrap">{msg.content}</p>
                    )}
                    
                    {translatedMessages[msg.id] && (
                      <div className="mt-2 pt-2 border-t border-white/20">
                        <p className="text-xs opacity-70 mb-1">Translation:</p>
                        <p className="text-sm whitespace-pre-wrap">{translatedMessages[msg.id]}</p>
                      </div>
                    )}
                    
                    <div className="flex items-center justify-between mt-1">
                      <p className={`text-xs ${isOwnMessage ? "text-primary-foreground/70" : "text-muted-foreground"}`}>
                        {formatTime(msg.created_at)}
                      </p>
                    </div>
                  </div>
                </MessageContextMenu>
                
                {isOwnMessage && (
                  <div className="w-8 h-8 rounded-full shrink-0 overflow-hidden brand-gradient flex items-center justify-center">
                    <span className="text-xs font-semibold text-primary-foreground">You</span>
                  </div>
                )}
              </motion.div>
            );
          })
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Attachment Menu */}
      <AnimatePresence>
        {showAttachments && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            className="px-4 pb-2"
          >
            <div className="glass rounded-2xl p-4">
              <div className="grid grid-cols-3 sm:grid-cols-6 gap-4">
                {attachmentOptions.map((option, index) => (
                  <motion.button
                    key={option.label}
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ delay: index * 0.05 }}
                    whileHover={{ scale: 1.1 }}
                    whileTap={{ scale: 0.95 }}
                    onClick={() => handleAttachmentAction(option.action)}
                  >
                    <div className="flex flex-col items-center gap-2">
                      <div className={`p-2 rounded-xl bg-gradient-to-br ${option.color} text-white`}>
                        <option.icon className="w-6 h-6" />
                      </div>
                      <span className="text-[10px] font-medium">{option.label}</span>
                    </div>
                  </motion.button>
                ))}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Voice Recorder */}
      <AnimatePresence>
        {showVoiceRecorder && (
          <div className="px-4 pb-2">
            <VoiceRecorder
              onSend={handleVoiceSend}
              onCancel={() => setShowVoiceRecorder(false)}
            />
          </div>
        )}
      </AnimatePresence>

      {/* Input Area */}
      {!showVoiceRecorder && (
        <div className="p-4 border-t border-slate-800/80 bg-[#10202a] shrink-0">
          {/* Reply Preview */}
          <AnimatePresence>
            {replyingTo && (
              <div className="mb-2">
                <ReplyBubble
                  replyToContent={replyingTo.content}
                  replyToSender={replyingTo.sender}
                  onClear={() => setReplyingTo(null)}
                />
              </div>
            )}
          </AnimatePresence>

          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              className="rounded-full shrink-0 text-slate-300 hover:text-slate-100"
              onClick={() => setShowAttachments(!showAttachments)}
            >
              <Paperclip className={`w-5 h-5 transition-transform ${showAttachments ? 'rotate-45' : ''}`} />
            </Button>

            <div className="flex-1 relative">
              <Input
                placeholder="Type a message..."
                className="pr-10 bg-slate-900/60 border-slate-800 text-slate-100 placeholder:text-slate-500 rounded-full"
                value={messageText}
                onChange={(e) => setMessageText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    handleSend();
                  }
                }}
              />
              <EmojiPicker
                onEmojiSelect={(emoji) => setMessageText(prev => prev + emoji)}
                trigger={
                  <Button
                    variant="ghost"
                    size="icon"
                    className="absolute right-1 top-1/2 -translate-y-1/2 w-8 h-8 rounded-full text-slate-300 hover:text-slate-100"
                  >
                    <Smile className="w-5 h-5" />
                  </Button>
                }
              />
            </div>

            {messageText.trim() ? (
              <Button
                variant="default"
                size="icon"
                className="rounded-full shrink-0 brand-gradient"
                onClick={handleSend}
                onMouseDown={handleSendButtonDown}
                onMouseUp={handleSendButtonUp}
                onMouseLeave={handleSendButtonUp}
                onTouchStart={handleSendButtonDown}
                onTouchEnd={handleSendButtonUp}
                title="Hold to schedule"
              >
                <Send className="w-5 h-5" />
              </Button>
            ) : (
              <Button
                variant="ghost"
                size="icon"
                className="rounded-full shrink-0 text-slate-300 hover:text-slate-100"
                onClick={() => setShowVoiceRecorder(true)}
              >
                <Mic className="w-5 h-5" />
              </Button>
            )}
          </div>
        </div>
      )}

      {/* Modals */}
      <VideoCallModal
        open={showVideoCall}
        onClose={() => setShowVideoCall(false)}
        contact={{ ...contact, user_id: contact.user_id }}
        isVideoCall={isVideoCall}
      />

      <EventCreator
        open={showEventCreator}
        onClose={() => setShowEventCreator(false)}
        onSendEvent={handleSendEvent}
      />

      <DocumentScanner
        open={showDocScanner}
        onClose={() => setShowDocScanner(false)}
        onScan={handleScanDocument}
      />

      <QRCodeScanner
        open={showQRScanner}
        onClose={() => setShowQRScanner(false)}
      />

      <ScheduleMessageDialog
        open={showScheduleDialog}
        onClose={() => setShowScheduleDialog(false)}
        onSchedule={handleScheduleMessage}
        messagePreview={messageText}
      />

      <AskAIDialog
        open={showAskAI}
        onClose={() => setShowAskAI(false)}
        onInsert={(text) => setMessageText(text)}
      />

      <AIArtStudio
        open={showAIArt}
        onClose={() => setShowAIArt(false)}
        onSendImage={handleAIArtSend}
      />

      <MultimodalAICall
        open={showAICall}
        onClose={() => setShowAICall(false)}
      />
    </div>
  );
};