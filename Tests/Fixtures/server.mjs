import { createServer } from "node:http";

// Synthetic loopback-only test gateway. It has no provider, database or real
// tokens. Never deploy this fixture or use it as an authentication example.
const receipts = new Map();
const conversation = (customer = "a") => ({ id: 7, status: "open", createdAt: 123, updatedAt: 123,
  unreadCount: 8, unreadForContact: 1, lastSeenAt: null, preview: `Support for synthetic customer ${customer}` });
const message = (content = "Hello from support", type = 1, id = 9) => ({ id, conversationId: 7, content,
  contentType: "text", contentAttributes: {}, messageType: type, createdAt: 123,
  sender: { name: type === 1 ? "Daykeeper support" : "You", avatarUrl: null }, attachments: [] });
const histories = new Map();
const createdCases = new Set();
const seenCustomers = new Set();
let origin;
const server = createServer(async (request, response) => {
  const url = new URL(request.url, origin);
  if (url.pathname === "/fixture/receipt") {
    response.writeHead(200, {"content-type":"application/json","cache-control":"no-store"});
    response.end(JSON.stringify(receipts.get(url.searchParams.get("case")) ?? {hits:0,sinkHits:0,cookies:[],methods:[]})); return;
  }
  const [, prefix, key, ...rest] = url.pathname.split("/");
  if (!key || !/^[a-z0-9-]{1,100}$/.test(key) || !["cases","sink"].includes(prefix)) {
    response.writeHead(404); response.end(); return;
  }
  const receipt = receipts.get(key) ?? { hits:0, sinkHits:0, cookies:[], methods:[], sends:0, seen:0, creates:0 };
  receipts.set(key, receipt);
  if (prefix === "sink") {
    receipt.sinkHits++;
    response.writeHead(200,{"content-type":"application/json"}); response.end(JSON.stringify({conversations:[],widgetConversationId:null})); return;
  }
  receipt.hits++; receipt.cookies.push(Boolean(request.headers.cookie)); receipt.methods.push(request.method);
  const path = `/${rest.join("/")}`;
  const customer = request.headers.authorization === "Bearer fixture-b" ? "b" : "a";
  const currentConversation = () => ({...conversation(customer), unreadForContact: seenCustomers.has(`${key}-${customer}`) ? 0 : 1});
  const json = (status, value, extra = {}) => {
    response.writeHead(status,{"content-type":"application/json","cache-control":"no-store",...extra}); response.end(JSON.stringify(value));
  };
  if (key.startsWith("redirect")) {
    const status = Number(key.slice(8,11));
    response.writeHead(status,{location:`${origin}/sink/${key}`});response.end();return;
  }
  if (key.startsWith("stallheaders")) return;
  if (key.startsWith("stallbody")) {response.writeHead(200,{"content-type":"application/json"});response.write('{"conversations":[');return;}
  if (key.startsWith("large")) {response.writeHead(200,{"content-type":"application/json"});response.end(' '.repeat(1_048_577));return;}
  if (key.startsWith("read401") && receipt.hits === 1) return json(401,{error:"expired_token"});
  if (key.startsWith("deny401")) return json(401,{error:{private:"not-safe"},retryable:false});
  if (key.startsWith("write401")) return json(401,{error:"expired_token",retryable:true});
  if (key.startsWith("write500")) return json(500,{error:"support_upstream_unavailable",retryable:true});
  if (path === "/v1/conversations") {
    if(request.method === "POST") {
      receipt.creates++; createdCases.add(key);
      if(key.startsWith("newcreation500"))return json(500,{error:"support_upstream_unavailable",retryable:true});
      return json(201,{conversation:currentConversation()});
    }
    return json(200,{conversations:key.startsWith("new") && !createdCases.has(key) ? [] : [currentConversation()],widgetConversationId:null},
      key.startsWith("cache") ? {"cache-control":"public, max-age=600",etag:'"synthetic-cache"'} :
      key.startsWith("cookie") ? {"set-cookie":"daykeeper_fixture=synthetic; Path=/; HttpOnly"} : {});
  }
  if (path === "/v1/conversations/7/seen") {receipt.seen++;seenCustomers.add(`${key}-${customer}`);return json(200,{conversationId:7,seen:true,seenAt:123});}
  if (path === "/v1/unread") {
    const conversation = currentConversation();
    return json(200,{unreadCount:conversation.unreadForContact,conversation:conversation.unreadForContact ? conversation : null,conversations:conversation.unreadForContact ? [conversation] : []});
  }
  if (path === "/v1/conversations/7/messages") {
    const historyKey = `${key}-${customer}`;
    const history = histories.get(historyKey) ?? (key.startsWith("new") ? [] : [message(`Hello from support for customer ${customer}`)]); histories.set(historyKey,history);
    if (request.method === "GET") return json(200,{messages:history});
    receipt.sends++;
    if(key.startsWith("quota"))return json(429,{error:"daykeeper_usage_limit_exceeded",retryable:false});
    let body="";
    for await (const bytes of request) {body+=bytes; if(body.length>100_000){response.writeHead(413);response.end();return;}}
    try {
      const input=JSON.parse(body), created=message(input.content,0,history.length+10);
      history.push(created);
      if(key.startsWith("accepted500"))return json(500,{error:"support_upstream_unavailable",retryable:true});
      return json(201,{message:created});
    } catch {return json(400,{error:"not_found"});}
  }
  json(404,{error:"not_found"});
});

server.listen(0,"127.0.0.1",()=>{
  origin=`http://127.0.0.1:${server.address().port}`;
  process.stdout.write(`${JSON.stringify({origin})}\n`);
});
function stop(){server.closeAllConnections();server.close();}
process.once("SIGINT",stop);process.once("SIGTERM",stop);
