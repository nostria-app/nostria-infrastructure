#!/usr/bin/env node
/**
 * Strfry plugin to validate and filter events for discovery relay sync
 * Only allows event kinds 3 (contact lists) and 10002 (relay lists)
 * 
 * Usage: Set this as pluginDown and/or pluginUp in strfry-router.conf
 */

const readline = require('readline');

// Allowed event kinds for discovery relay sync
const ALLOWED_KINDS = [3, 10002];

// Event kind descriptions for logging
const KIND_DESCRIPTIONS = {
    3: "contact list",
    10002: "relay list"
};

function processEvent(event) {
    try {
        // Parse the event if it's a string
        const parsedEvent = typeof event === 'string' ? JSON.parse(event) : event;
        
        // Check if event kind is allowed
        if (!ALLOWED_KINDS.includes(parsedEvent.kind)) {
            console.error(`Rejecting event kind ${parsedEvent.kind} (not in allowed kinds: ${ALLOWED_KINDS.join(', ')})`);
            return {
                action: "reject",
                msg: `Event kind ${parsedEvent.kind} not allowed for discovery relay sync`
            };
        }
        
        // Basic validation
        if (!parsedEvent.id || !parsedEvent.pubkey || !parsedEvent.created_at || !parsedEvent.sig) {
            console.error(`Rejecting malformed event: missing required fields`);
            return {
                action: "reject",
                msg: "Event missing required fields"
            };
        }
        
        // Log accepted event
        const kindDesc = KIND_DESCRIPTIONS[parsedEvent.kind] || `kind ${parsedEvent.kind}`;
        console.log(`Accepting ${kindDesc} event from ${parsedEvent.pubkey.substring(0, 8)}...`);
        
        return {
            action: "accept",
            msg: ""
        };
        
    } catch (error) {
        console.error(`Error processing event: ${error.message}`);
        return {
            action: "reject",
            msg: `Plugin error: ${error.message}`
        };
    }
}

// Main plugin loop
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

console.error('Discovery relay sync plugin started - filtering for kinds 3 and 10002');

rl.on('line', (line) => {
    try {
        const request = JSON.parse(line);
        const result = processEvent(request.event);
        
        // Send response back to strfry
        console.log(JSON.stringify(result));
        
    } catch (error) {
        console.error(`Plugin error: ${error.message}`);
        console.log(JSON.stringify({
            action: "reject",
            msg: `Plugin parsing error: ${error.message}`
        }));
    }
});

rl.on('close', () => {
    console.error('Discovery relay sync plugin shutting down');
    process.exit(0);
});

// Handle termination signals
process.on('SIGTERM', () => {
    console.error('Discovery relay sync plugin received SIGTERM');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.error('Discovery relay sync plugin received SIGINT');
    process.exit(0);
});
