const { PeerServer } = require('peer');

const port = process.env.PORT || 9000;

const peerServer = PeerServer({
  port: port,
  path: '/',
  proxied: true, // Required for Render/Heroku (behind load balancer)
  debug: true
});

console.log(`ONO PeerServer running on port ${port}`);

peerServer.on('connection', (client) => {
  console.log('Client connected:', client.getId());
});

peerServer.on('disconnect', (client) => {
  console.log('Client disconnected:', client.getId());
});
