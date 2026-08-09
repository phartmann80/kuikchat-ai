import { StaticLayout } from "@/components/layout/StaticLayout";

const PrivacyPage = () => {
    return (
        <StaticLayout
            title="Privacy Policy"
            subtitle="How we collect, use, and protect your personal information."
        >
            <div className="prose prose-muted max-w-none">
                <h3 className="text-2xl font-bold mb-4">1. Data Collection</h3>
                <p className="mb-6">
                    KuikChat is built on the principle of data minimization. We only collect the information necessary to provide you with a secure and functional messaging experience.
                </p>
                <h3 className="text-2xl font-bold mb-4">2. Message access controls</h3>
                <p className="mb-6">
                    KuikChat uses authenticated access and database row-level security so only authorized conversation members can read or write messages through the product APIs. Message content is not end-to-end encrypted at the application layer today, so KuikChat operators with privileged server access could access stored message content. Do not treat chats as unreadably private from the service.
                </p>
                <h3 className="text-2xl font-bold mb-4">3. AI Features</h3>
                <p className="mb-6">
                    Our AI features are designed with privacy in mind. Where possible, processing happens on your device. When cloud processing is required, your data is anonymized and never stored for training purposes.
                </p>
            </div>
        </StaticLayout>
    );
};

export default PrivacyPage;
