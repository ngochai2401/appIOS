const WebSocket = require("ws");
const wss = new WebSocket.Server({ port: 8080 });

const rooms = new Map();           // roomId → Set<WebSocket>
const roomDeleteTimers = new Map(); // roomId → Timer
const ROOM_EXPIRE_MS = 60000;      // 60 giây

function send(ws, data) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(data));
}

function broadcast(roomId, sender, data) {
  const clients = rooms.get(roomId);
  if (!clients) return;

  console.log(`[ROOM ${roomId}] broadcast: ${data.type}`);

  for (const client of clients) {
    if (client !== sender && client.readyState === WebSocket.OPEN) {
      send(client, data);
    }
  }
}

function broadcastAll(roomId, data) {
  const clients = rooms.get(roomId);
  if (!clients) return;

  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      send(client, data);
    }
  }
}

// ==================== XỬ LÝ RỜI PHÒNG ====================
function removeSocketFromRoom(ws, reason = "normal") {
  if (!ws.roomId) return;

  const roomId = ws.roomId;
  const clients = rooms.get(roomId);
  if (!clients) return;

  const peerId = ws.peerId || "unknown";
  const role = ws.role || "unknown";

  const wasPresent = clients.has(ws);
  if (wasPresent) {
    clients.delete(ws);
    console.log(`Peer ${peerId} (${role}) left room ${roomId}. Reason: ${reason}`);
    console.log(`Room ${roomId} size = ${clients.size}`);
  }

  // Thông báo cho người còn lại
  if (clients.size > 0 && wasPresent) {
    broadcast(roomId, ws, {
      type: "peer-left",
      roomId,
      senderId: peerId,
      role,
      payload: {
        message: `Master đã kết thúc phòng ${peerId}.`,
        reason: reason,               // "normal", "kicked", "disconnected", "closed"
        timestamp: Date.now()
      },
    });
  }

  // Reset thông tin client
  ws.roomId = null;
  ws.peerId = null;
  ws.role = null;

  // Nếu phòng trống → bắt đầu đếm ngược xóa phòng
  if (clients.size === 0) {
    if (roomDeleteTimers.has(roomId)) return;

    console.log(`Room ${roomId} is now empty → will be deleted after ${ROOM_EXPIRE_MS/1000}s if no one rejoins.`);

    const timer = setTimeout(() => {
      const currentClients = rooms.get(roomId);
      if (currentClients && currentClients.size === 0) {
        console.log(`Room ${roomId} deleted after timeout`);

        broadcastAll(roomId, {
          type: "room-expired",
          roomId,
          senderId: "server",
          payload: {
            message: "Phòng đã hết hạn do không có kết nối trong 60 giây.",
          },
        });

        rooms.delete(roomId);
      }
      roomDeleteTimers.delete(roomId);
    }, ROOM_EXPIRE_MS);

    roomDeleteTimers.set(roomId, timer);
  }
}

// ==================== KẾT NỐI MỚI ====================
wss.on("connection", (ws) => {
  console.log("New client connected");
  
  ws.roomId = null;
  ws.peerId = null;
  ws.role = null;
  ws.isAlive = true;

  ws.on("pong", () => { ws.isAlive = true; });

  ws.on("message", (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      console.log("RECEIVE:", msg);

      if (msg.type === "ping") {
        send(ws, { type: "pong", roomId: msg.roomId || ws.roomId || "" });
        return;
      }

      // ===================== JOIN ROOM =====================
      if (msg.type === "join") {
        const { roomId, senderId, role } = msg;

        if (!roomId || !senderId || !role) {
          send(ws, { type: "error", payload: { message: "Thiếu thông tin roomId, senderId hoặc role." } });
          return;
        }

        // Hủy timer xóa phòng nếu có người vào lại
        if (roomDeleteTimers.has(roomId)) {
          clearTimeout(roomDeleteTimers.get(roomId));
          roomDeleteTimers.delete(roomId);
          console.log(`Room ${roomId} timer cancelled - peer rejoined`);
        }

        if (!rooms.has(roomId)) {
          if (role === "master") {
            rooms.set(roomId, new Set());
            console.log(`New room ${roomId} created by master ${senderId}`);
          } else {
            send(ws, { 
              type: "error", 
              payload: { message: "Phòng chưa tồn tại. Viewer không thể vào trước master." } 
            });
            return;
          }
        }

        // Rời phòng cũ nếu đang ở phòng khác
        if (ws.roomId && ws.roomId !== roomId) {
          removeSocketFromRoom(ws, "switch-room");
        }

        ws.roomId = roomId;
        ws.peerId = senderId;
        ws.role = role;

        const clients = rooms.get(roomId);
        clients.add(ws);

        console.log(`Peer ${senderId} (${role}) joined room ${roomId} | Size: ${clients.size}`);

        send(ws, { type: "joined", roomId, senderId: "server" });

        // Thông báo cho người khác trong phòng
        broadcast(roomId, ws, {
          type: "peer-joined",
          roomId,
          senderId,
          role,
        });

        return;
      }

      // ===================== LEAVE =====================
      if (msg.type === "leave") {
        const roomId = ws.roomId;
        if (!roomId) return;

        removeSocketFromRoom(ws, "normal");
        send(ws, { 
          type: "left", 
          roomId, 
          senderId: "server", 
          payload: { message: "Bạn đã rời phòng." } 
        });
        return;
      }

      // ===================== KHÁC =====================
      if (!ws.roomId || !rooms.has(ws.roomId)) {
        send(ws, { type: "error", payload: { message: "Bạn chưa tham gia phòng hoặc phòng không tồn tại." } });
        return;
      }

      // Forward các message khác (offer, answer, ice-candidate, command...)
      broadcast(ws.roomId, ws, msg);

    } catch (e) {
      console.error("Message error:", e);
      send(ws, { type: "error", payload: { message: e.toString() } });
    }
  });

  ws.on("close", () => {
    console.log(`Socket closed: ${ws.peerId || "unknown"} (${ws.role || "unknown"})`);
    removeSocketFromRoom(ws, "closed");
  });

  ws.on("error", (err) => {
    console.error("Socket error:", err.message);
    removeSocketFromRoom(ws, "error");
  });
});

// ==================== HEARTBEAT (60s) ====================
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      console.log(`Terminating inactive client: ${ws.peerId || "unknown"}`);
      if (ws.readyState === WebSocket.OPEN) {
        send(ws, {
          type: "kicked",
          payload: { message: "Bạn đã bị ngắt kết nối do mất kết nối quá lâu." }
        });
      }
      removeSocketFromRoom(ws, "timeout");
      ws.terminate();
      return;
    }

    ws.isAlive = false;
    try {
      ws.ping();
    } catch (e) {
      removeSocketFromRoom(ws, "ping-failed");
      ws.terminate();
    }
  });
}, 30000); // ping mỗi 30 giây
// ==================== APP-LEVEL PING (5s) ====================
// Thêm đoạn này ngay bên dưới heartbeatInterval
const pingInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN && ws.roomId) {
      send(ws, { type: "ping", roomId: ws.roomId || "" });
    }
  });
}, 5000);


wss.on("close", () => {
  clearInterval(heartbeatInterval);
  clearInterval(pingInterval);
});

console.log("Signaling server running at ws://0.0.0.0:8080");