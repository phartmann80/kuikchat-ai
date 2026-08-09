import { motion } from "framer-motion";
import { Shield, Lock, Eye, UserCheck, Server, FileKey } from "lucide-react";

const privacyFeatures = [
  {
    icon: Lock,
    title: "Authenticated access",
    description: "Conversations are protected by account authentication and database access controls for members only.",
  },
  {
    icon: Eye,
    title: "No Data Selling",
    description: "Your data is yours. We never sell, share, or monetize your personal information. Ever.",
  },
  {
    icon: Server,
    title: "Minimal Data Collection",
    description: "We only collect what's absolutely necessary to provide our service. Nothing more.",
  },
  {
    icon: UserCheck,
    title: "Verified Profiles",
    description: "Optional verification badges ensure you're always talking to who you think you are.",
  },
  {
    icon: FileKey,
    title: "Honest security wording",
    description: "We do not claim end-to-end encryption for message bodies until a verified E2E design ships.",
  },
  {
    icon: Shield,
    title: "Row-level protections",
    description: "Server-side policies restrict who can read and write chat data through the product APIs.",
  },
];

export const Privacy = () => {
  return (
    <section id="privacy" className="py-24 relative overflow-hidden">
      {/* Background */}
      <div className="absolute inset-0 bg-gradient-to-br from-primary/5 via-background to-secondary/5" />
      
      <div className="container mx-auto px-4 relative z-10">
        <div className="grid lg:grid-cols-2 gap-12 items-center">
          {/* Left Content */}
          <motion.div
            initial={{ opacity: 0, x: -30 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6 }}
          >
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-secondary/10 mb-6">
              <Shield className="w-4 h-4 text-secondary" />
              <span className="text-sm font-medium text-secondary">Privacy First</span>
            </div>
            
            <h2 className="text-3xl sm:text-4xl md:text-5xl font-bold mb-6 leading-tight">
              Your Privacy is{" "}
              <span className="brand-gradient-text">Non-Negotiable</span>
            </h2>
            
            <p className="text-lg text-muted-foreground mb-8">
              In a world where data is currency, we believe your conversations should remain private. 
              KuikChat is built from the ground up with privacy as the foundation, not an afterthought.
            </p>

            {/* Trust Badges */}
            <div className="flex flex-wrap gap-4">
              <div className="glass rounded-full px-4 py-2 flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-secondary animate-pulse" />
                <span className="text-sm font-medium">GDPR Compliant</span>
              </div>
              <div className="glass rounded-full px-4 py-2 flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-secondary animate-pulse" />
                <span className="text-sm font-medium">SOC 2 Certified</span>
              </div>
              <div className="glass rounded-full px-4 py-2 flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-secondary animate-pulse" />
                <span className="text-sm font-medium">Zero Knowledge</span>
              </div>
            </div>
          </motion.div>

          {/* Right Content - Features Grid */}
          <motion.div
            initial={{ opacity: 0, x: 30 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="grid grid-cols-1 sm:grid-cols-2 gap-4"
          >
            {privacyFeatures.map((feature, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: index * 0.1 }}
                whileHover={{ scale: 1.02 }}
                className="glass rounded-xl p-4 hover:shadow-lg transition-all duration-300"
              >
                <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-secondary to-primary flex items-center justify-center mb-3">
                  <feature.icon className="w-5 h-5 text-primary-foreground" />
                </div>
                <h3 className="font-semibold mb-1">{feature.title}</h3>
                <p className="text-sm text-muted-foreground">{feature.description}</p>
              </motion.div>
            ))}
          </motion.div>
        </div>
      </div>
    </section>
  );
};
