class SCGI::Request {

    has $!strict = True;
    has $.connection;
    has %.env is rw;
    has $.body is rw;
    has $.request is rw;
    has $!closed is rw = 0;

    method err (
        $message, 
        $status = "Status: 500 SCGI Protocol Error";
    ) {
        my $crlf = "\x0D\x0A" x 2;
        $*ERR.say: "[{time}] $message";
        $.connection.send("$status$crlf");
        self.close;
        return 0;
    }

    method shutdown (:$message="Server Shutdown (by request)", :$status) {
        self.err($message, $status);
        exit;
    }

    method parse {
        $.request = $.connection.recv();
        if $.request ~~ / ^ (\d+) \: / {
            my $length = +$0;
            my $offset = ~$0.chars + 1;
            my $env_string = $.request.substr($offset, $length);
            my $comma = $.request.substr($offset+$length, 1);
            ## Does not work in Rakudo new master.
            #return self.err("malformed netstring, expecting terminating comma, found \"$comma\"") if $comma ne ',';
            ## Begin replacement.
            if $comma ne ',' {
                return self.err("malformed netstring, expecting terminating comma, found \"$comma\"");
            }
            ## End replacement.
            $.body = $.request.substr($offset+$length+1);
            my @env = $env_string.split("\0");
            @env.pop;
            %.env = @env;
            if $!strict {
                ## Does not work in Rakudo new master.
                #return self.err("malformed or missing CONTENT_LENGTH header")\
                #unless defined %.env<CONTENT_LENGTH> \
                #&& %.env<CONTENT_LENGTH> ~~ / ^ \d+ $ /;
                ## Begin replacement.
                unless defined %.env<CONTENT_LENGTH> && %.env<CONTENT_LENGTH> ~~ / ^ \d+ $ / {
                    return self.err("malformed or missing CONTENT_LENGTH header");
                }
                ## End replacement.
                ## Does not work in Rakudo new master.
                #return self.err("missing SCGI header")\
                #unless %.env<SCGI> && %.env<SCGI> eq '1';
                ## Begin replacement.
                unless %.env<SCGI> && %.env<SCGI> eq '1' {
                    return self.err: "missing SCGI header";
                }
                ## End replacement.
            }
            return 1;
        }
        elsif $.request ~~ /:s ^ QUIT $ / {
            self.shutdown(:status<Server Shutdown>);
        }
        else {
            return self.err(
                "invalid request, expected a netstring, got: $.request"
            );
        }
    }

    method close () {
        $.connection.close if $.connection;
        $!closed = 1;
    }

    submethod DESTROY {
        self.close unless $.closed;
    }

}

class SCGI {

    has Int $!port = 8080;
    has Str $!addr = 'localhost';
    ## The following doesn't work on Rakudo new master.
    #has IO::Socket 
    ## Removing the IO::Socket part allows it to compile.
    has $.socket = IO::Socket::INET.socket(2, 1, 6)\
                                              .bind($!addr, $!port)\
                                              .listen();

    has $!bodykey    = 'SCGI.Body';
    has $!requestkey = 'SCGI.Request';
    has $!scgikey    = 'SCGI.Object';

    has $!strict = True;
    
    method accept () {
        my $connection = self.socket.accept() or return;
        SCGI::Request.new( :connection($connection), :strict($!strict) );
    }

    method handle (&closure) {
        while (my $request = self.accept) {
            if $request.parse {
                my %env = $request.env;
                %env{$!requestkey} = $request;
                %env{$!scgikey} = self;
                %env{$!bodykey} = $request.body; 
                $request.connection.send(closure(%env));
                $request.close;
            }
        }
    }

    method shutdown {
        ## Not as graceful as using the request shutdown.
        $*ERR.say: "[{time}] Server Shutdown (direct)";
        exit;
    }

}
