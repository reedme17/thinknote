import { createThinknoteServer } from "./src/app.js";
import { loadConfig } from "./src/config.js";

const config = loadConfig();
const app = await createThinknoteServer({ config });

app.server.listen(config.port, () => {
    app.logger.info("server_listening", {
        port: config.port,
        provider: app.services.ai.providerName,
        retrievalProvider: app.services.retrieval.providerName
    });
});
