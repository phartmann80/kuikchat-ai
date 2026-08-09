import { ChevronLeft, HelpCircle, MessageCircle, FileText, ExternalLink, Mail, Globe } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { useNavigate } from "react-router-dom";

interface HelpSettingsProps {
  onBack: () => void;
}

const faqItems = [
  {
    question: "How do I send a message?",
    answer: "Tap on a contact from your chat list, type your message in the text field at the bottom, and tap the send button or press Enter."
  },
  {
    question: "How do I make a voice or video call?",
    answer: "Open a chat with the contact you want to call, then tap the phone icon for voice calls or the video icon for video calls in the top right corner."
  },
  {
    question: "Are my messages encrypted?",
    answer: "KuikChat protects accounts with authentication and database access controls. Message content is not end-to-end encrypted today, so do not treat chats as unreadably private from the service."
  },
  {
    question: "How do I create a group?",
    answer: "Go to the Chats tab, tap the new chat button, select 'New Group', add participants, give your group a name, and tap Create."
  },
  {
    question: "How do I block someone?",
    answer: "Open the chat with the contact, tap on their name at the top, scroll down and tap 'Block'. You can unblock them later from Settings > Privacy > Blocked contacts."
  },
  {
    question: "How do I use disappearing messages?",
    answer: "Open a chat, tap the contact's name, and select 'Disappearing messages'. Choose how long messages should last before they're automatically deleted."
  },
];

const helpLinks = [
  { icon: Globe, label: "Help Center", description: "Browse articles and tutorials", path: "/#about" },
  { icon: Mail, label: "Contact Us", description: "Get in touch with support", path: "/#contact" },
  { icon: FileText, label: "Terms of Service", description: "Read our terms", path: "/#privacy" },
  { icon: FileText, label: "Privacy Policy", description: "How we handle your data", path: "/#privacy" },
];

export const HelpSettings = ({ onBack }: HelpSettingsProps) => {
  const navigate = useNavigate();

  const handleLinkClick = (path: string) => {
    navigate(path);
  };

  return (
    <div className="flex-1 flex flex-col bg-card">
      <div className="p-4 border-b border-border flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={onBack} className="rounded-full">
          <ChevronLeft className="w-5 h-5" />
        </Button>
        <h2 className="text-xl font-semibold">Help</h2>
      </div>

      <ScrollArea className="flex-1">
        <div className="p-4 space-y-6">
          {/* Quick Help */}
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center">
                <HelpCircle className="w-5 h-5 text-primary" />
              </div>
              <h3 className="font-medium">Frequently Asked Questions</h3>
            </div>

            <Accordion type="single" collapsible className="w-full">
              {faqItems.map((item, index) => (
                <AccordionItem key={index} value={`item-${index}`}>
                  <AccordionTrigger className="text-left text-sm">
                    {item.question}
                  </AccordionTrigger>
                  <AccordionContent className="text-muted-foreground text-sm">
                    {item.answer}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </div>

          {/* Contact & Resources */}
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-secondary/20 flex items-center justify-center">
                <MessageCircle className="w-5 h-5 text-secondary" />
              </div>
              <h3 className="font-medium">Contact & Resources</h3>
            </div>

            <div className="space-y-2">
              {helpLinks.map((link) => (
                <button 
                  key={link.label}
                  onClick={() => handleLinkClick(link.path)}
                  className="w-full flex items-center justify-between p-3 rounded-lg hover:bg-muted/30 cursor-pointer transition-colors text-left"
                >
                  <div className="flex items-center gap-3">
                    <link.icon className="w-5 h-5 text-muted-foreground" />
                    <div>
                      <p className="font-medium">{link.label}</p>
                      <p className="text-sm text-muted-foreground">{link.description}</p>
                    </div>
                  </div>
                  <ExternalLink className="w-4 h-4 text-muted-foreground" />
                </button>
              ))}
            </div>
          </div>

          {/* Report a Problem */}
          <div className="p-4 rounded-xl bg-muted/30 border border-border">
            <h4 className="font-medium mb-2">Report a problem</h4>
            <p className="text-sm text-muted-foreground mb-4">
              Having issues with the app? Let us know and we'll help you out.
            </p>
            <Button className="brand-gradient w-full">
              <Mail className="w-4 h-4 mr-2" />
              Send Feedback
            </Button>
          </div>
        </div>
      </ScrollArea>
    </div>
  );
};
