package Test::CGI::External;
use 5.006;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw//;
use warnings;
use strict;
use Carp;
use Gzip::Faster;
use File::Temp 'tempfile';
use Test::Builder;
use FindBin '$Bin';

our $VERSION = '0.07';

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
    if ($^O eq 'MSWin32') {
	$self->pass_test ('Invalid test for MS Windows');
    }
    else {
	# These tests don't do anything useful on Windows, see
	# http://perldoc.perl.org/perlport.html#-X

	if (! -x $cgi_executable) {
	    $self->fail_test ("The CGI executable '$cgi_executable' exists but is not executable");
	}
	else {
	    $self->pass_test ("$cgi_executable is executable");
	}
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
    my ($o, $name, $value) = @_;
    if (! $o->{set_env}) {
        $o->{set_env} = [$name];
    }
    else {
        push @{$o->{set_env}}, $name;
    }
    if ($ENV{$name}) {
        carp "A variable '$name' is already set in the environment.\n";
    }
    $ENV{$name} = $value;
}

# Internal routine to run a CGI program.

sub run_private
{
    my ($o) = @_;

    # Pull everything out of the object and into normal variables.

    my $verbose = $o->{verbose};
    my $options = $o->{run_options};
    my $cgi_executable = $o->{cgi_executable};
    my $comp_test = $o->{comp_test};

    # Hassle up the CGI inputs, including environment variables, from
    # the options the user has given.

    # mwforum requires GATEWAY_INTERFACE to be set to CGI/1.1
    setenv_private ($o, 'GATEWAY_INTERFACE', 'CGI/1.1');

    my $query_string = $options->{QUERY_STRING};
    if (defined $query_string) {
        if ($verbose) {
            $o->{tb}->note ("I am setting the query string to '$query_string'.\n");
        }
        setenv_private ($o, 'QUERY_STRING', $query_string);
    }
    elsif ($verbose) {
	$o->{tb}->note ("There is no query string.\n");
    }
    my $request_method = check_request_method ($options->{REQUEST_METHOD});
    if ($verbose) {
	$o->{tb}->note ("The request method is '$request_method'.\n");
    }
    setenv_private ($o, 'REQUEST_METHOD', $request_method);
    my $content_type = $options->{CONTENT_TYPE};
    if ($content_type) {
	if ($verbose) {
	    $o->{tb}->note ("The content type is '$content_type'.\n");
	}
	setenv_private ($o, 'CONTENT_TYPE', $content_type);
    }
    if ($options->{HTTP_COOKIE}) {
        setenv_private ($o, 'HTTP_COOKIE', $options->{HTTP_COOKIE});
    }
    my $remote_addr = $o->{run_options}->{REMOTE_ADDR};
    if ($remote_addr) {
        if ($verbose) {
	    $o->{tb}->note ("I am setting the remote address to '$remote_addr'.\n");
        }
        setenv_private ($o, 'REMOTE_ADDR', $remote_addr);
    }
    my $input;
    if (defined $options->{input}) {
        $o->{input} = $options->{input};
        my $content_length = length ($input);
        setenv_private ($o, 'CONTENT_LENGTH', $content_length);
        if ($verbose) {
	    $o->{tb}->note ("I am setting the CGI program's standard input to a string of length $content_length taken from the input options.\n");
        }
    }

    if ($comp_test) {
        if ($verbose) {
	    $o->{tb}->note ("I am requesting gzip encoding from the CGI executable.\n");
        }
        setenv_private ($o, 'HTTP_ACCEPT_ENCODING', 'gzip, fake');
    }

    # Actually run the executable under the current circumstances.

    my @cmd = ($cgi_executable);
    if ($o->{command_line_options}) {
	push @cmd, @{$o->{command_line_options}};
    }
    if ($verbose) {
	$o->{tb}->note ("I am running '@cmd'\n");
    }
    $o->run3 (\@cmd);
    $options->{output} = $o->{output};
    $options->{errors} = $o->{errors};
    if ($verbose) {
	$o->{tb}->note (sprintf ("The program has now finished running. There were %d bytes of output.\n", length ($o->{output})));
    }
    $options->{exit_code} = $?;
    if ($options->{expect_failure}) {
    }
    else {
	if ($options->{exit_code} != 0) {
	    my $message = "The CGI executable exited with non-zero status";
	    $o->fail_test ($message);
	}
	else {
	    $o->pass_test ("The CGI executable exited with a zero status");
	}
    }
    if (! $options->{output}) {
        $o->fail_test ("The CGI executable produced some output");
    }
    else {
        $o->pass_test ("The CGI executable produced some output");
    }
    if ($options->{expect_errors}) {
	if ($options->{error_output}) {
	    $o->pass_test ("The CGI executable produced some output on the error stream as follows:\n$o->{errors}\n");
	}
	else {
	    $o->fail_test ("The CGI executable did not produce any output on the error stream");
	}
    }
    else {
	if ($o->{errors}) {
	    $o->fail_test ("The CGI executable produced some output on the error stream as follows:\n$o->{errors}\n");
	}
	else {
	    $o->pass_test ("The CGI executable did not produce any output on the error stream");
	}
    }

    $o->tidy_files ();

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
    my ($o, $header, $verbose) = @_;

    my $expected_charset = $o->{expected_charset};
    my $content_type_line;

    if ($verbose) {
        print "# I am checking to see if the output contains a valid content type line.\n";
    }
    my $content_type_ok;
    if ($header =~ m!(Content-Type:\s*.*)!i) {
        $o->pass_test ("There is a Content-Type header");
        $content_type_line = $1;
        if ($content_type_line =~ m!^Content-Type:(?:$HTTP_LWS)+
                                        (?:$HTTP_TOKEN)+
                                        /
                                        (?:$HTTP_TOKEN)+
                                   !xi) {
            $o->pass_test ("The Content-Type header is well-formed");
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
                        $o->fail_test ("You told me to expect a charset value of '$expected_charset', but the content-type line of the CGI executable, '$content_type_line', contains a charset parameter with the value '$charset'");
                    }
                    else {
                        $content_type_ok = 1;
                        $o->pass_test ("The charset '$charset' corresponds to the one you said to expect, '$expected_charset'");
                    }
                }
                else {
                    $o->fail_test ("You told me to expect a charset (character set) value of '$expected_charset', but the content-type line of the CGI executable, '$content_type_line', does not contain a valid 'charset' parameter");
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
            $o->fail_test ("The Content-Type line '$content_type_line' does not match the specification required.");
        }
    }
    else {
        $o->fail_test ("There is no 'Content-Type' line in the output.");
    }
    if ($content_type_ok && $verbose) {
        print "# The content-type line appears to be OK.\n";
    }
}

sub check_http_header_syntax_private
{
    my ($o, $header, $verbose) = @_;
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
                $o->fail_test ("The output of the CGI executable has a blank line as its first line");
            }
            else {
                $o->pass_test ("There are $line_number valid header lines");
            }
            # We have finished looking at the headers.
            last;
        }
        $line_number += 1;
        if ($line !~ $line_re) {
            $o->fail_test ("The header on line $line_number, '$line', appears not to be a correctly-formed HTTP header");
            $bad_headers++;
        }
        else {
            $o->pass_test ("The header on line $line_number, '$line', appears to be a correctly-formed HTTP header");
        }
    }
    if ($verbose) {
        print "# I have finished checking the HTTP header for consistency.\n";
    }
}

# Check whether the headers of the CGI output are well-formed.

sub check_headers_private
{
    my ($o) = @_;

    # Extract variables from the object

    my $verbose = $o->{verbose};
    my $output = $o->{run_options}->{output};
    if (! $output) {
        return;
    }
    my ($header, $body) = split /\r?\n\r?\n/, $output, 2;
    check_http_header_syntax_private ($o, $header, $verbose);
    if (! $o->{no_check_content}) {
        check_content_line_private ($o, $header, $verbose);
    }

    $o->{run_options}->{header} = $header;
    $o->{run_options}->{body} = $body;
}

sub check_compression_private
{
    my ($o) = @_;
    my $body = $o->{run_options}->{body};
    my $header = $o->{run_options}->{header};
    my $verbose = $o->{verbose};
    if ($verbose) {
        print "# I am testing whether compression has been applied to the output.\n";
    }
    if ($header !~ /Content-Encoding:.*\bgzip\b/i) {
        $o->fail_test ("Output '$header' does not have a header indicating compression");
    }
    else {
        $o->pass_test ("The header claims that the output is compressed");
        my $uncompressed;
        #printf "The length of the body is %d\n", length ($body);
	eval {
	    $uncompressed = gunzip $body;
	};
        if ($@) {
            $o->fail_test ("Output claims to be in gzip format but gunzip on the output failed with the error '$@'");
            my $failedfile = "$0.gunzip-failure.$$";
            open my $temp, ">:bytes", $failedfile or die $!;
            print $temp $body;
            close $temp or die $!;
            print "# Saved failed output to $failedfile.\n";
        }
        else {
            my $uncomp_size = length $uncompressed;
            my $percent_comp = sprintf ("%.1f%%", (100 * length ($body)) / $uncomp_size);
            $o->pass_test ("The body of the CGI output was able to be decompressed using 'gunzip'. The uncompressed size is $uncomp_size. The compressed output is $percent_comp of the uncompressed size.");
            
            $o->{run_options}->{body} = $uncompressed;
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
    my $output = $self->{run_options}->{output};
    # Jump over the following tests if there is no output. This used
    # to complain a lot about output and fail tests but this proved a
    # huge nuisance when creating TODO tests, so just skip over the
    # output tests if we have already failed the basic "did not
    # produce output" issue.
    if ($output) {
	check_headers_private ($self);
	if ($self->{comp_test}) {
	    check_compression_private ($self);
	}
    }
    if ($options->{html}) {
	validate_html ($self);
    }
    if ($options->{die_on_failure}) {
        if ($self->{failures} > 0) {
            croak "You have selected 'die on failure'. I am dying due to $self->{failures} failed tests.\n";
        }
    }
    for my $e (@{$self->{set_env}}) {
#        print "Deleting environment variable $e\n";
        $ENV{$e} = undef;
    }
    $self->{set_env} = undef;
}

sub tidy_files
{
    my ($o) = @_;
    if ($o->{infile}) {
	unlink $o->{infile} or die $!;
    }

    # Insert HTML test here?

    unlink $o->{outfile} or die $!;
    unlink $o->{errfile} or die $!;
}

sub run3
{
    my ($o, $exe) = @_;
    my $cmd = "@$exe";
    my $infile;
    if (defined $o->{input}) {
	my $in;
	($in, $o->{infile}) = tempfile ("/tmp/input-XXXXXX");
	binmode $in, ":raw";
	print $in $o->{input};
	close $in or die $!;
	$cmd .= " < $infile";
    }
    my $out;
    ($out, $o->{outfile}) = tempfile ("/tmp/output-XXXXXX");
    close $out or die $!;
    my $err;
    ($err, $o->{errfile}) = tempfile ("/tmp/errors-XXXXXX");
    close $err or die $!;
  
    my $status = system ("$cmd > $o->{outfile} 2> $o->{errfile}");

    $o->{output} = '';
    if (-f $o->{outfile}) {
	open my $out, "<", $o->{outfile} or die $!;
	while (<$out>) {
	    $o->{output} .= $_;
	}
	close $out or die $!;
    }
    $o->{errors} = '';
    if (-f $o->{errfile}) {
	open my $err, "<", $o->{errfile} or die $!;
	while (<$err>) {
	    $o->{errors} .= $_;
	}
	close $err or die $!;
    }

#    print "OUTPUT IS $o->{output}\n";
#    print "$$errors\n";
#    exit;

    return $status;
}

sub validate_html
{
    my ($o) = @_;
    my $html_validate = "$Bin/html-validate-temp-out.$$";
    my $html_temp_file = "$Bin/html-validate-temp.$$.html";
    open my $htmltovalidate, ">", $html_temp_file or die $!;
    print $htmltovalidate $o->{run_options}->{body};
    close $htmltovalidate or die $!;
    my $status = system ("/home/ben/bin/validate $html_temp_file > $html_validate");
    
    if (-s $html_validate) {
	$o->fail_test ("HTML is valid");
	open my $in, "<", $html_validate or die $!;
	while (<$in>) {
	    note ($_);
	}
	close $in or die $!;
    }
    else {
	$o->pass_test ("HTML is valid");
    }
    unlink $html_temp_file or die $!;
    if (-f $html_validate) {

	unlink $html_validate or die $!;
    }
}

1;

