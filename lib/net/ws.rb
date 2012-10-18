require "net/http"
require "uri"
require "base64"
require "digest/sha1"


module URI
  class WS < HTTP; end

  @@schemes["WS"] = WS
  @@schemes["WSS"] = WS
end


module Net

  class WS < HTTP
    class Error < StandardError ; end

    FIN_FALSE = 0
    FIN_TRUE = 1
    HEADER_ACCEPT = "Sec-WebSocket-Accept".freeze
    HEADER_CONNECTION = "Connection".freeze
    HEADER_CONNECTION_VALUE = "Upgrade".freeze
    HEADER_EXTENSIONS = "Sec-WebSocket-Extensions".freeze
    HEADER_KEY = "Sec-WebSocket-Key".freeze
    HEADER_SUBPROTOCOL = "Sec-WebSocket-Protocol".freeze
    HEADER_UPGRADE = "Upgrade".freeze
    HEADER_UPGRADE_VALUE = "websocket".freeze
    HEADER_VERSION = "Sec-WebSocket-Version".freeze
    HEADER_VERSION_VALUE = "13".freeze
    LENGTH_IS_16BIT = 126
    LENGTH_IS_64BIT = 127
    OPCODE_CLOSE = 0x08
    OPCODE_PING = 0x09
    OPCODE_PONG = 0x0A
    OPCODE_TEXT = 0x01
    SEC_WEBSOCKET_KEY_LEN = 16
    SEC_WEBSOCKET_SUFFIX = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11".freeze
    STATE_CLOSING = "state_closing".freeze
    STATE_CONNECTED = "state_connected".freeze
    STATE_CONNECTING = "state_connecting".freeze
    STATE_FINISHED = "state_finished".freeze
    UNSIGNED_16BIT_MAX = (2**16) - 1
    UNSIGNED_64BIT_MAX = (2**64) - 1
    WEBSOCKET_SCHEME_WS = "ws".freeze
    WEBSOCKET_SCHEME_WSS = "wss".freeze
    WEBSOCKET_SCHEMES = [WEBSOCKET_SCHEME_WS, WEBSOCKET_SCHEME_WSS].freeze

    def initialize(uri, options=nil)
      options ||= {}
      @uri = URI(uri)
      @on_message = options[:on_message]
      @subprotocols = options[:subprotocols].is_a?(Array) ? \
        options[:subprotocols] : \
        [options[:subprocotols]]
      @connection_state = nil

      super(@uri.host, @uri.port)
    end

    def to_io
      @socket.io
    end

    def open(request_uri=nil)
      return false if STATE_CONNECTING == @connection_state

      @connection_state = STATE_CONNECTING
      @request_uri = request_uri || @uri.request_uri || "/"

      perform_opening_handshake.tap do |successful|
        @connection_state = STATE_CONNECTED if successful
      end
    end

    def ping(message=nil)
      send_frame(FIN_TRUE, 0, OPCODE_PING, message)
      receive_frame
    end

    def close
      _send_close
      Timeout.timeout(10) {receive_frame}
    rescue Timeout::Error
      finish
    end

    def send_text(data)
      # TODO fragmentation
      send_frame(FIN_TRUE, 0, OPCODE_TEXT, data)
    end

    def receive_message
      # TODO fragmentation
      receive_frame
    end


    protected

    def finish
      super
      @connection_state = STATE_FINISHED
    end

    def _send_close
      send_frame(FIN_TRUE, 0, OPCODE_CLOSE)
      @connection_state = STATE_CLOSING
    end

    def receive_frame
      header = @socket.read(2).unpack("n").first
      fin = (header >> 15) & 0x1
      rsv = (header >> 12) & 0x7
      opcode = (header >> 8) & 0xF
      masked = ((header >> 7) & 0x1) > 0
      length = extract_length(header)

      raise NotImplementedError, "Fragmentation is not supported" unless fin

      extract_payload(masked, length).tap do |payload|
        if control_frame?(opcode)
          handle_control_frame(opcode, payload)
        else
          @on_message.call(payload) if @on_message
        end
      end
    end

    def extract_payload(masked, length)
      if masked
        extract_masked_payload(length)
      else
        extract_unmasked_payload(length)
      end
    end

    def extract_masked_payload(length)
      $stderr.puts("Warning: Masked server response received. " +
                   "This should never happen.")
      masking_key = @socket.read(4).unpack("CCCC")

      unmask(masking_key, extract_unmasked_payload(length))
    end

    def extract_unmasked_payload(length)
      @socket.read(length)
    end

    # Control frames are identified by opcodes where the most significant bit
    # of the opcode is 1.
    # -- http://tools.ietf.org/html/rfc6455#section-5.5
    #
    # Since there are presently 4 bits used for the opcode, the most
    # significant bit is the "8" bit.
    def control_frame?(opcode)
      (opcode & 0x8) > 0
    end

    def extract_length(header)
      length_code = header & 0x7f

      case length_code
      when LENGTH_IS_16BIT
        @socket.read(2).unpack("n").first
      when LENGTH_IS_64BIT
        @socket.read(8).unpack("NN").inject(0) do |sum, int|
          (sum << 32) + int
        end
      else
        length_code
      end
    end

    def handle_control_frame(opcode, payload=nil)
      case opcode
      when OPCODE_CLOSE
        _send_close unless STATE_CLOSING == @connection_state
        finish
      when OPCODE_PING
        pong(payload)
      when OPCODE_PONG
        payload
      else
        fail_websocket_connection("Unhandled opcode: #{opcode.inspect}")
      end
    end

    def pong(payload)
      send_frame(FIN_TRUE, 0, OPCODE_PONG, payload)
    end

    def send_frame(fin, rsv, opcode, payload=nil)
      send_frame_header(fin, rsv, opcode)
      send_mask_flag_and_payload_size(payload)
      masking_key = send_masking_key
      send_frame_payload(payload, masking_key)
    end

    def send_frame_header(fin, rsv, opcode)
      bytes = []

      bytes << (fin << 7) + (rsv << 4) + opcode

      @socket.write(bytes.pack("C*"))
    end

    def send_mask_flag_and_payload_size(payload)
      mask_flag = (1 << 7)

      if payload.nil?
        @socket.write [mask_flag].pack("C")
      elsif payload.size < LENGTH_IS_16BIT
        @socket.write [mask_flag + payload.size].pack("C")
      elsif payload.size <= UNSIGNED_16BIT_MAX
        @socket.write [mask_flag + 126].pack("C")
        @socket.write [payload.size].pack("n*")
      elsif payload.size <= UNSIGNED_64BIT_MAX
        @socket.write [mask_flag + 127, payload.size].pack("C")
        @socket.write [payload.size].pack("n*")
      else
        raise Error, "Unhandled payload size: #{payload.size.inspect}"
      end
    end

    def send_masking_key
      generate_masking_key.tap do |key|
        @socket.write key.pack("CCCC")
      end
    end

    def send_frame_payload(payload, masking_key)
      return unless payload

      # FIXME we only support text for now
      @socket.write(mask(payload.unpack("U*"), masking_key).pack("C*"))
    end

    def mask(payload, key)
      i = 0

      payload.map do |octet|
        masked = octet ^ key[i % 4]
        i += 1
        masked
      end
    end

    def generate_masking_key
      val = rand(2**32)
      [val >> 24, (val >> 16) & 0x0f, (val >> 8) & 0x0f, val & 0x0f]
    end

    def perform_opening_handshake
      unless STATE_CONNECTING == @connection_state
        raise Error, "Connection state error"
      end

      response = send_opening_handshake
      handle_opening_handshake_response(response)
    end

    def send_opening_handshake
      headers = {
        HEADER_UPGRADE => HEADER_UPGRADE_VALUE,
        HEADER_CONNECTION => HEADER_CONNECTION_VALUE,
        HEADER_KEY => generate_sec_websocket_key,
        HEADER_VERSION => HEADER_VERSION_VALUE,
        HEADER_SUBPROTOCOL => @subprotocols.join(","),
      }

      get = Net::HTTP::Get.new(@request_uri, headers)

      start
      request(get)
    end

    def generate_sec_websocket_key
      c = []

      SEC_WEBSOCKET_KEY_LEN.times {c << "%c" % [rand(127)]}

      @sec_websocket_key = Base64.encode64(c.join("")).strip
    end

    def handle_opening_handshake_response(response)
      case response.code
      when "101"
        validate_opening_handshake_response(response)
      else
        raise Error, "Unhandled opening handshake response #{response.inspect}"
      end
    end

    def validate_opening_handshake_response(response)
      unless valid_upgrade_header?(response[HEADER_UPGRADE])
        fail_websocket_connection("Upgrade header")
      end

      unless valid_connection_header?(response[HEADER_CONNECTION])
        fail_websocket_connection("Connection header")
      end

      unless valid_sec_websocket_accept_header?(response[HEADER_ACCEPT])
        fail_websocket_connection("Sec-WebSocket-Accept header")
      end

      unless valid_sec_websocket_extensions_header?(response[HEADER_EXTENSIONS])
        fail_websocket_connection("Sec-WebSocket-Extensions header")
      end

      unless valid_sec_websocket_subprotocol_header?(response[HEADER_SUBPROTOCOL])
        fail_websocket_connection("Sec-WebSocket-Subprotocol header")
      end

      true
    end

    def valid_upgrade_header?(upgrade_header="")
      /websocket/i === upgrade_header
    end

    def fail_websocket_connection(reason="Unknown reason")
      raise Error, "Fail websocket connection: #{reason.inspect}."
    end

    def valid_connection_header?(connection_header="")
      /upgrade/i === connection_header
    end

    def valid_sec_websocket_accept_header?(header_value)
      header_value &&
        expected_sec_websocket_accept_header == header_value.strip
    end

    def expected_sec_websocket_accept_header
      payload = @sec_websocket_key + SEC_WEBSOCKET_SUFFIX

      Base64.encode64(Digest::SHA1.digest(payload)).strip
    end

    def valid_sec_websocket_extensions_header?(header_value="")
      nil_or_empty?(header_value)
    end

    def nil_or_empty?(value)
      value.nil? || value.strip.empty?
    end

    def valid_sec_websocket_subprotocol_header?(header_value="")
      nil_or_empty?(header_value)
    end
  end
end
