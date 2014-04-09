package Test::CGI::External;
use 5.006;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw//;
use warnings;
use strict;
use Carp;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IPC::Run3;
#use File::Temp 'tempfile';
use Test::Builder;

our $VERSION = '0.02';

sub new
{
    my %tester;
    for my $t (qw/tests failures successes/) {
        $tester{$t} = 0;
    }

    my $tb = Test::Builder->new ();
    $tester{tb} = $tb;

    return bless \%tester;
}

sub set_cgi_executable
{
    my ($self, $cgi_executable, @command_line_options) = @_;
    if ($self->{verbose}) {
        $self->{tb}->note ("I am setting the CGI executable to be tested to '$cgi_executable'.\n");
    }
    if (! -f $cgi_executable) {
        $self->fail_test ("I cannot find a file corresponding to CGI executable '$cgi_executable'");
    }
    else {
	$self->pass_test ("found executable $cgi_executable");
    }
    if (! -x $cgi_executable) {
        $self->fail_test ("The CGI executable '$cgi_executable' exists but is not executable");
    }
    else {
	$self->pass_test ("$cgi_executable is executable");
    }
    $self->{cgi_executable} = $cgi_executable;
    if (@command_line_options) {
	$self->{command_line_options} = \@command_line_options;
    }
    else {
	$self->{command_line_options} = [];
    }
}

sub do_compression_test
{
    my ($self, $switch) = @_;
    $switch = !! $switch;
    if ($self->{verbose}) {
	my $msg = "You have asked me to turn ";
        if ($switch) {
            $msg .= "on";
        }
        else {
            $msg .= "off";
        }
        $msg .= " testing of compression.\n";
	$self->{tb}->note ($msg);
    }
    $self->{comp_test} = $switch;
}

sub expect_charset
{
    my ($self, $charset) = @_;
    if ($self->{verbose}) {
	$self->{tb}->note ("You have told me to expect a 'charset' value of '$charset'.\n");
    }
    $self->{expected_charset} = $charset;
}

sub set_verbosity
{
    my ($self, $verbosity) = @_;
    $self->{verbose} = !! $verbosity;
    if ($self->{verbose}) {
        $self->{tb}->note ("# You have asked ", __PACKAGE__, " to print messages as it works.\n");
    }
}

sub check_request_method
{
    my ($request_method) = @_;
    my $default_request_method = 'GET';
    if ($request_method) {
        my @request_method_list = qw/POST GET HEAD/;
        my %valid_request_method = map {$_ => 1} @request_method_list;
        if ($request_method && ! $valid_request_method{$request_method}) {
            carp "You have set the request method to a value '$request_method' which is not one of the ones I know about, which are ", join (', ', @request_method_list), " so I am setting it to the default, '$default_request_method'";
            $request_method = $default_request_method;
        }
    }
    else {
        carp "You have not set the request method, so I am setting it to the default, '$default_request_method'";
        $request_method = $default_request_method;
    }
    return $request_method;
}

# Register a successful test

sub pass_test
{
    my ($self, $test) = @_;
    $self->{successes} += 1;
    $self->{tests} += 1;

    $self->{tb}->ok (1, $test);

#    print "ok $self->{tests} - $test.\n";
}

# Fail a test and keep going.

sub fail_test
{
    my ($self, $test) = @_;
    $self->{failures} += 1;
    $self->{tests} += 1;

    $self->{tb}->ok (0, $test);

#    print "not ok $self->{tests} - $test.\n";
}

# Print the TAP plan

sub plan
{
    my ($self) = @_;
    $self->{tb}->done_testing ();
    #print "1..$self->{tests}\n";
}

# Fail a test which means that we cannot keep going.

sub abort_test
{
    my ($self, $test) = @_;
    $self->{tb}->skip_all ($test);
}

sub setenv_private
{
    my ($object, $name, $value) = @_;
    if (! $object->{set_env}) {
        $object->{set_env} = [$name];
    }
    else {
        push @{$object->{set_env}}, $name;
    }
    if ($ENV{$name}) {
        carp "A variable '$name' is already set in the environment.\n";
    }
    $ENV{$name} = $value;
}

# Internal routine to run a CGI program.

sub run_private
{
    my ($object) = @_;

    # Pull everything out of the object and into normal variables.

    my $verbose = $object->{verbose};
    my $options = $object->{run_options};
    my $cgi_executable = $object->{cgi_executable};
    my $comp_test = $object->{comp_test};

    # Hassle up the CGI inputs, including environment variables, from
    # the options the user has given.

    # mwforum requires GATEWAY_INTERFACE to be set to CGI/1.1
    setenv_private ($object, 'GATEWAY_INTERFACE', 'CGI/1.1');

    my $query_string = $options->{QUERY_STRING};
    if (defined $query_string) {
        if ($verbose) {
            $object->{tb}->note ("I am setting the query string to '$query_string'.\n");
        }
        setenv_private ($object, 'QUERY_STRING', $query_string);
    }
    elsif ($verbose) {
	$object->{tb}->note ("There is no query string.\n");
    }
    my $request_method = check_request_method ($options->{REQUEST_METHOD});
    if ($verbose) {
	$object->{tb}->note ("The request method is '$request_method'.\n");
    }
    setenv_private ($object, 'REQUEST_METHOD', $request_method);
    my $content_type = $options->{CONTENT_TYPE};
    if ($content_type) {
	if ($verbose) {
	    $object->{tb}->note ("The content type is '$content_type'.\n");
	}
	setenv_private ($object, 'CONTENT_TYPE', $content_type);
    }
    if ($options->{HTTP_COOKIE}) {
        setenv_private ($object, 'HTTP_COOKIE', $options->{HTTP_COOKIE});
    }
    my $remote_addr = $object->{run_options}->{REMOTE_ADDR};
    if ($remote_addr) {
        if ($verbose) {
	    $object->{tb}->note ("I am setting the remote address to '$remote_addr'.\n");
        }
        setenv_private ($object, 'REMOTE_ADDR', $remote_addr);
    }
    my $input;
    if ($options->{input}) {
        $input = $options->{input};
        my $content_length = length ($input);
        setenv_private ($object, 'CONTENT_LENGTH', $content_length);
        if ($verbose) {
	    $object->{tb}->note ("I am setting the CGI program's standard input to a string of length $content_length taken from the input options.\n");
        }
    }

    if ($comp_test) {
        if ($verbose) {
	    $object->{tb}->note ("I am requesting gzip encoding from the CGI executable.\n");
        }
        setenv_private ($object, 'HTTP_ACCEPT_ENCODING', 'gzip, fake');
    }

    # Actually run the executable under the current circumstances.

    my $standard_output;
    my $error_output;
    if ($verbose) {
        	$object->{tb}->note ("I am running the program.\n");
    }
    run3 ([$cgi_executable, @{$object->{command_line_options}}],
	  \$input, \$standard_output, \$error_output);
    if ($verbose) {
	$object->{tb}->note (sprintf ("The program has now finished running. There were %d bytes of output.\n", length ($standard_output)));
    }
    $options->{exit_code} = $?;
    if ($options->{exit_code} != 0) {
        my $message = "The CGI executable exited with non-zero status. ";
        if ($error_output) {
            $message .= "It printed the following message:\n$error_output\n";
        }
        else {
            $message .= "It did not print any message on the error stream.\n";
        }
        $object->fail_test ($message);
    }
    else {
        $object->pass_test ("The CGI executable exited with a zero status");
    }
    $options->{output} = $standard_output;
    if (! $options->{output}) {
        $object->abort_test ("The CGI executable did not produce any output");
    }
    else {
        $object->pass_test ("The CGI executable produced some output");
    }
    $options->{error_output} = $error_output;
    if ($error_output) {
        $object->fail_test ("The CGI executable produced some output on the error stream as follows:\n$error_output\n");
    }
    else {
        $object->pass_test ("The CGI executable did not produce any output on the error stream");
    }

    return;
}


# my %token_valid_chars;
# @token_valid_chars{0..127} = (1) x 128;
# my @ctls = (0..31,127);
# @token_valid_chars{@ctls} = (0) x @ctls;
# my @tspecials = 
#     ('(', ')', '<', '>', '@', ',', ';', ':', '\\', '"',
#      '/', '[', ']', '?', '=', '{', '}', \x32, \x09 );
# @token_valid_chars{@tspecials} = (0) x @tspecials;

# These regexes are for testing the validity of the HTTP headers
# produced by the CGI script.

my $HTTP_CTL = qr/[\x{0}-\x{1F}\x{7f}]/;

my $HTTP_TSPECIALS = qr/[\x{09}\x{20}\x{22}\x{28}\x{29}\x{2C}\x{2F}\x{3A}-\x{3F}\x{5B}-\x{5D}\x{7B}\x{7D}]/;

my $HTTP_TOKEN = '[\x{21}\x{23}-\x{27}\x{2a}\x{2b}\x{2d}\x{2e}\x{30}-\x{39}\x{40}-\x{5a}\x{5e}-\x{7A}\x{7c}\x{7e}]';

my $HTTP_TEXT = qr/[^\x{0}-\x{1F}\x{7f}]/;

# This does not include [CRLF].

my $HTTP_LWS = '[\x{09}\x{20}]';

my $qd_text = qr/[^"\x{0}-\x{1f}\x{7f}]/;
my $quoted_string = qr/"$qd_text+"/;
my $field_content = qr/(?:$HTTP_TEXT)*|
                       (?:
                           $HTTP_TOKEN|
                           $HTTP_TSPECIALS|
                           $quoted_string
                       )*
                      /x;

my $http_token = qr/(?:$HTTP_TOKEN)+/;

# Check for a valid content type line.

sub check_content_line_private
{
    my ($object, $header, $verbose) = @_;

    my $expected_charset = $object->{expected_charset};
    my $content_type_line;

    if ($verbose) {
        print "# I am checking to see if the output contains a valid content type line.\n";
    }
    my $content_type_ok;
    if ($header =~ m!(Content-Type:\s*.*)!i) {
        $object->pass_test ("There is a Content-Type header");
        $content_type_line = $1;
        if ($content_type_line =~ m!^Content-Type:(?:$HTTP_LWS)+
                                        (?:$HTTP_TOKEN)+
                                        /
                                        (?:$HTTP_TOKEN)+
                                   !xi) {
            $object->pass_test ("The Content-Type header is well-formed");
            if ($expected_charset) {
                if ($content_type_line =~ /charset
                                           =
                                           (
                                               $http_token|
                                               $quoted_string
                                           )/xi) {
                    my $charset = $1;
                    $charset =~ s/^"(.*)"$/$1/;
                    if (lc $charset ne lc $expected_charset) {
                        $object->fail_test ("You told me to expect a charset value of '$expected_charset', but the content-type line of the CGI executable, '$content_type_line', contains a charset parameter with the value '$charset'");
                    }
                    else {
                        $content_type_ok = 1;
                        $object->pass_test ("The charset '$charset' corresponds to the one you said to expect, '$expected_charset'");
                    }
                }
                else {
                    $object->fail_test ("You told me to expect a charset (character set) value of '$expected_charset', but the content-type line of the CGI executable, '$content_type_line', does not contain a valid 'charset' parameter");
                }
            }
            else {
                $content_type_ok = 1;
                if ($verbose) {
                    print "# I am not testing for the 'charset' parameter.\n";
                }
            }
        }
        else {
            $object->fail_test ("The Content-Type line '$content_type_line' does not match the specification required.");
        }
    }
    else {
        $object->fail_test ("There is no 'Content-Type' line in the output.");
    }
    if ($content_type_ok && $verbose) {
        print "# The content-type line appears to be OK.\n";
    }
}

sub check_http_header_syntax_private
{
    my ($object, $header, $verbose) = @_;
    if ($verbose) {
        print "# I am checking the HTTP header produced.\n";
    }
    my @lines = split /\r?\n/, $header;
    my $line_number = 0;
    my $bad_headers = 0;
    my $line_re = qr/$HTTP_TOKEN+:$HTTP_LWS+/;
#    print "Line regex is $line_re\n";
    for my $line (@lines) {
        if ($line =~ /^$/) {
            if ($line_number == 0) {
                $object->fail_test ("The output of the CGI executable has a blank line as its first line");
            }
            else {
                $object->pass_test ("There are $line_number valid header lines");
            }
            # We have finished looking at the headers.
            last;
        }
        $line_number += 1;
        if ($line !~ $line_re) {
            $object->fail_test ("The header on line $line_number, '$line', appears not to be a correctly-formed HTTP header");
            $bad_headers++;
        }
        else {
            $object->pass_test ("The header on line $line_number, '$line', appears to be a correctly-formed HTTP header");
        }
    }
    if ($verbose) {
        print "# I have finished checking the HTTP header for consistency.\n";
    }
}

# Check whether the headers of the CGI output are well-formed.

sub check_headers_private
{
    my ($object) = @_;

    # Extract variables from the object

    my $verbose = $object->{verbose};
    my $output = $object->{run_options}->{output};
    if (! $output) {
        die "An error has occured in ", __PACKAGE__, ": the output should have been checked for emptiness but somehow it hasn't been, and so I cannot continue working. Sorry!";
    }
    my ($header, $body) = split /\r?\n\r?\n/, $output, 2;
    check_http_header_syntax_private ($object, $header, $verbose);
    if (! $object->{no_check_content}) {
        check_content_line_private ($object, $header, $verbose);
    }
    $object->{run_options}->{header} = $header;
    $object->{run_options}->{body} = $body;
}

sub check_compression_private
{
    my ($object) = @_;
    my $body = $object->{run_options}->{body};
    my $header = $object->{run_options}->{header};
    my $verbose = $object->{verbose};
    if ($verbose) {
        print "# I am testing whether compression has been applied to the output.\n";
    }
    if ($header !~ /Content-Encoding:.*\bgzip\b/i) {
        $object->fail_test ("Output '$header' does not have a header indicating compression");
    }
    else {
        $object->pass_test ("The header claims that the output is compressed");
        my $uncompressed;
        #printf "The length of the body is %d\n", length ($body);
        my $status = gunzip \$body => \$uncompressed;
        if (! $status) {
            $object->fail_test ("Output claims to be in gzip format but gunzip on the output failed with the error '$GunzipError'");
            my $failedfile = "$0.gunzip-failure.$$";
            open my $temp, ">:bytes", $failedfile or die $!;
            print $temp $body;
            close $temp or die $!;
            print "# Saved failed output to $failedfile.\n";
        }
        else {
            my $uncomp_size = length $uncompressed;
            my $percent_comp = sprintf ("%.1f%%", (100 * length ($body)) / $uncomp_size);
            $object->pass_test ("The body of the CGI output was able to be decompressed using 'gunzip'. The uncompressed size is $uncomp_size. The compressed output is $percent_comp of the uncompressed size.");
            
            $object->{run_options}->{body} = $uncompressed;
        }
    }
    if ($verbose) {
        print "# I have finished testing the compression.\n";
    }
}

sub set_no_check_content
{
    my ($self, $value) = @_;
    my $verbose = $self->{verbose};
    if ($verbose) {
        print "# I am setting no content check to $value.\n";
    }
    $self->{no_check_content} = $value;
}

sub run
{
    my ($self, $options) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    if (! $self->{cgi_executable}) {
        croak "You have requested me to run a CGI executable with 'run' without telling me what it is you want me to run. Please tell me the name of the CGI executable using the method 'set_cgi_executable'.";
    }
    if (! $options) {
        $self->{run_options} = {};
        carp "You have requested me to run a CGI executable with 'run' without specifying a hash reference to store the input, output, and error output. I can only run basic tests of correctness";
    }
    else {
        $self->{run_options} = $options;
    }
    if ($self->{verbose}) {
        print "# I am commencing the testing of CGI executable '$self->{cgi_executable}'.\n";
    }
#    eval {
    run_private ($self);
    check_headers_private ($self);
    if ($self->{comp_test}) {
        check_compression_private ($self);
    }
    if ($options->{die_on_failure}) {
        if ($self->{failures} > 0) {
            croak "You have selected 'die on failure'. I am dying due to $self->{failures} failed tests.\n";
        }
    }
    else {
        $self->{tb}->note ("# There were $self->{tests} tests. Of these, $self->{successes} succeeded and $self->{failures} failed.\n");
    }
    for my $e (@{$self->{set_env}}) {
#        print "Deleting environment variable $e\n";
        $ENV{$e} = undef;
    }
    $self->{set_env} = undef;
}

# The following is a replacement for IPC::Run3's "run3". 

# sub run3
# {
#     my ($exe, $input, $output, $errors) = @_;
#     my $cmd = "@$exe";
#     my $infile;
#     if ($$input) {
# 	(my $in, $infile) = tempfile ("input-XXXXXX");
# 	binmode $in, ":raw";
# 	print $in $$input;
# 	close $in or die $!;
# 	$cmd .= " < $infile";
#     }
#     my ($out, $outfile) = tempfile ("output-XXXXXX");
#     close $out or die $!;
#     my ($err, $errfile) = tempfile ("errors-XXXXXX");
#     close $err or die $!;
    
#     my $status = system ("$cmd > $outfile 2> $errfile");

#     $$output = '';
#     if (-f $outfile) {
# 	open my $out, "<", $outfile or die $!;
# 	while (<$out>) {
# 	    $$output .= $_;
# 	}
# 	close $out or die $!;
#     }
#     $$errors = '';
#     if (-f $errfile) {
# 	open my $err, "<", $errfile or die $!;
# 	while (<$err>) {
# 	    $$errors .= $_;
# 	}
# 	close $err or die $!;
#     }

# #    print "$$output\n";
# #    print "$$errors\n";
# #    exit;

#     if ($infile) {
# 	unlink $infile or die $!;
#     }
#     unlink $outfile or die $!;
#     unlink $errfile or die $!;
#     return $status;
# }

1;

