package Net::DSLProvider::Cerberus;
use base 'Net::DSLProvider';
use Net::DSLProvider::Cerberus::soap;
use Time::Piece;
use Time::Seconds;
use Date::Holidays::EnglandWales;
use LWP;
__PACKAGE__->mk_accessors(qw/clientid dslcheckuser dslcheckpass/);

my %fields = (
    Wsfinddslline => [ qw/ cli / ],
    Wsdslgetstats => [ qw/ cli / ],
    Wsupdateprofile => [ qw/ cli "interleave-code" "snr-code" / ],
    Wssubmitorder => [ qw/ cli "client-ref" forename surname company
        street city postcode sex email ordertype "losing-isp" mac
        "prod-id" "inst-id" "ip-id" "maint-id" "serv-id" "del-pref"
        contract devices "ripe-justification" "skip-line-check" / ],
        );

sub _credentials {
    my $self = shift;
    return SOAP::Header->new(
      name =>'AuthenticatedUser',
      attr => { xmlns => "http://nc.cerberusnetworks.co.uk/NetCONNECT" },
      value => {username => $self->{user}, password => $self->{pass} },
    );
}

sub _call { 
    my ($self, $method, @args) = @_;
    Net::DSLProvider::Cerberus::soap->$method(@args, $self->_credentials);
}

sub make_request {
    my ($self, $method, %args) = @_;

    my @args = ();

    for my $key ( @{$fields{$method}} ) {
        push @args, $args{$key};
    }
    push @args, $self->clientid;

    my $resp = Net::DSLProvider::Cerberus::soap->$method(@args, $self->_credentials);
    return $resp;
}

sub order {
    my ($self, %args) = @_;

    # Go through the parameters below and remove those that are not mandatory
    # and those which are covered in the base package sigs{} definition.
    $self->_check_params(\%args, qw/cli client-ref forename surname company
        street city postcode sex email ordertype losing-isp mac prod-id
        inst-id ip-id maint-id serv-id del-pref contract devices
        ripe-justification skip-line-check /);

    my %resp = $self->make_request("Wssubmitorder", %args);

}

sub services_available {
    my ($self, %args) = @_;

    # Note that this function is different to all the others as it uses a
    # call via LWP to get the data rather than submitting via XML as all 
    # the others do.

    my $ua = new LWP::UserAgent;
    my $agent = __PACKAGE__ . '/0.1 ';
    my $url = 'http://checker.cerberusnetworks.co.uk/cgi-bin/externaldslcheck.cgi?pstn='.$args{cli}.'&user='.$self->{dslcheckuser}.'&pass='.$self->{dslcheckpass};
    my $req = new HTTP::Request 'GET' => $url;
    my $res = $ua->request($req);

    my ($up, $down, $status, $line_length) = split(/ /, $res->content);
    $up =~ s/ADSL2PLUS_ANNEXA_UP_ESTIMATE=(.*)/$1/;
    $down =~ s/ADSL2PLUS_ANNEXA_DOWN_ESTIMATE=(.*)/$1/;
    $status =~ s/ADSL2PLUS_STATUS=(\d+)/$1/;
    $line_length =~ s/BT_LINE_LENGTH=(\d+)/$1/;

    die "No service available" unless $status < 2;

    my $t = Time::Piece->new();
    $t += ONE_WEEK;
    while ( is_uk_holiday($t->ymd) || ($t->wday == 1 || $t->wday == 7) ) {
        $t += ONE_DAY;
    }

    my @sv = ();
    push @sv, { 'product_id' => 'DS 006013',
                'product_name' => 'LLU Up to 8Mb ADSL2+ Home Connection',
                'max_speed' => $down,
                'first_date' => $t->ymd };

    push @sv, { 'product_id' => 'DS 006010',
                'product_name' => 'LLU Premium Up to 24Mb ADSL2+ Standard Connection',
                'max_speed' => $down,
                'first_date' => $t->ymd };

    push @sv, { 'product_id' => 'DS 006013',
                'product_name' => 'LLU Premium Up to 24Mb ADSL2+ Business Connection inc 1 Static IP',
                'max_speed' => $down,
                'first_date' => $t->ymd };

    return @sv;
}

sub service_view {
    my ($self, %args) = @_;
    foreach ( @{$fields{Wsfinddslline}} ) {
        die "Provide the $_ parameter" unless $args{$_};
    }

    # my %input = $self->convert_input(%args);

    my $resp = $self->make_request("Wsfinddslline", %args);

    return %{$resp->{Xml_DSLLines}};
}

1;
