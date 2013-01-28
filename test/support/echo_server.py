#!/usr/bin/env python2.7 -u -Wall

import sys
from twisted.internet import reactor
from twisted.python import log
from autobahn.websocket import WebSocketServerFactory, \
                               WebSocketServerProtocol, \
                               listenWS


class EchoServerProtocol(WebSocketServerProtocol):

   def onMessage(self, msg, binary):
      self.sendMessage(msg, binary)

   def onClose(self, *args):
      reactor.stop()


if __name__ == '__main__':
   factory = WebSocketServerFactory("ws://localhost:9001", debug = True, debugCodePaths = True)
   log.startLogging(sys.stdout)
   factory.protocol = EchoServerProtocol
   listenWS(factory)
   print "Here we go"
   sys.stdout.flush() # flush the line so that tests know we're up
   sys.stderr.flush()
   reactor.run()
