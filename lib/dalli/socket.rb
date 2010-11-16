begin
  require 'kgio'
  puts "Using kgio socket IO" if $TESTING

  class Dalli::Server::KSocket < Kgio::Socket
    attr_accessor :options
    
    def wait_readable
      IO.select([self], nil, nil, options[:timeout]) || raise(Timeout::Error, "IO timeout")
    end

    def wait_writable
      IO.select(nil, [self], nil, options[:timeout]) || raise(Timeout::Error, "IO timeout")
    end

    def self.open(host, port, options = {})
      addr = Socket.pack_sockaddr_in(port, host)
      sock = start(addr)
      sock.options = options
      sock.wait_writable
      sock
    end

    alias :write :kgio_write

    def readfull(count)
      value = ''
      loop do
        value << kgio_read!(count - value.bytesize)
        break if value.bytesize == count
      end 
      value
    end

  end

  ::Kgio.wait_readable = :wait_readable
  ::Kgio.wait_writable = :wait_writable

rescue LoadError
  puts "Using standard socket IO" if $TESTING

  class Dalli::Server::KSocket < Socket
    attr_accessor :options
    
    def self.open(host, port, options = {})
      # All this ugly code to ensure proper Socket connect timeout
      addr = Socket.getaddrinfo(host, nil)
      sock = new(Socket.const_get(addr[0][0]), Socket::SOCK_STREAM, 0)
      sock.options = options
      begin
        sock.connect_nonblock(Socket.pack_sockaddr_in(port, addr[0][3]))
      rescue Errno::EINPROGRESS
        resp = IO.select(nil, [sock], nil, sock.options[:timeout])
        begin
          sock.connect_nonblock(Socket.pack_sockaddr_in(port, addr[0][3]))
        rescue Errno::EISCONN
        end
      end
      sock
    end
  
    def readfull(count)
      value = ''
      begin
        loop do
          value << sysread(count - value.bytesize)
          break if value.bytesize == count
        end
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK
        if IO.select([self], nil, nil, options[:timeout])
          retry
        else
          raise Timeout::Error, "IO timeout"
        end
      end
      value
    end

  end

end