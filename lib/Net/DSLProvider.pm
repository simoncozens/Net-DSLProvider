package Net::DSLProvider;
use warnings;
use strict;
use base 'Class::Accessor';
use Carp qw/croak/;
our $VERSION = '0.01';
__PACKAGE__->mk_accessors(qw/user pass debug testing/);

=head1 NAME

Net::DSLProvider - Standardized interface to various DSL providers

=head1 SYNOPSIS

    use Net::DSLProvider;
    my $p = Net::DSLProvider::SomeISP->new(user => $u, pass => $p);
    ...

=head1 DESCRIPTION

This class doesn't do much - please see the individual
Net::DSLProvider::* modules instead. The purpose of this class is to
provide useful auxiliary functions to individual provider modules, and
also to define the methods, parameters and expected output format
provided by each module. Provider modules B<must> massage their
parameters and output into the specifications of this module.

=cut

my %sigs;

sub _check_params {
    my ($self, $args, @additional) = @_;
    my $method = ((caller(1))[3]);
    $method =~ s/.*:://;
    my @signature = @{$sigs{$method}};
    for (@signature, @additional) {
        my $ok = 0;
        my @poss = split /\|/, $_; 
        for (@poss) { $ok=1 if $args->{$_} };
        croak "You must supply the $poss[0] parameter" if !$ok and @poss==1;
        croak "You must supply at least one of the following parameters: @poss" 
            if !$ok;
    }
}

=head1 METHODS

=head1 INFORMATIONAL METHODS

These methods tell you things.

=head2 services_available

Takes a phone number or a postcode and returns a list of services
that the provider can deliver to the given line.

Parameters:

    cli / postcode (Required)
    mac (Optional)

Output is an array of hash references. Each hash reference may contain
the following keys:

    first_date
    product_name
    product_id (Required)

=cut

$sigs{services_available} = ["cli|postcode"];

=head2 order_updates_since
            
    $p->order_updates_since( date => "2009-12-01 00:01:01" );
            
Returns all the BT order updates since the given date in ISO8601 format.

Output is an array of hash references. Each hash reference may contain
the following keys:

    order_id 
    date 
    name 
    value

=cut

$sigs{order_updates_since} = ["date"];

=head2 verify_mac

Given a cli and MAC returns 1 if the MAC is valid.

Parameters:

    cli (Required)
    mac (Required)

=cut

$sigs{verify_mac} = [qw/cli mac/];

=head2 usage_summary

Gets a summary of usage in the given month. Inputs are service-id, year, month.

Returns a hash with the following fields:

    year, month, username, total-sessions, total-session-time,
    total-input-octets, total-output-octets

Input octets are upload bandwidth. Output octets are download bandwidth.

=cut

$sigs{usage_summary} = [qw/service-id year month/];

=head2 order_history

Gets order history for the given order ID. Input is C<order-id>.
    
Returns an array, each element of which is a hash showing the next
update in date sorted order. The hash keys are date, name and value.
    


=head1 EXECUTIVE METHODS

=head2 order

    $enta->order(
        # Customer details
        forename => "Clara", surname => "Trucker", company => "ABC Ltd",
        building => "123", street => "Pigeon Street", city => "Manchester", 
        county => "Greater Manchester", postcode => "M1 2JX",
        telephone => "01614960213", email => "clare@example.com",
        # Order details
        clid => "01614960213", "client-ref" => "claradsl", 
        "prod-id" => $product, crd => $leadtime, username => "claraandhugo",
        password => "skyr153", "care-level" => "standard", 
        realm => "surfdsl.net"
    );

Submits an order for DSL to be provided to the specified phone line.
Note that all the parameters above must be supplied. CRD is the
requested delivery date in YYYY-mm-dd format; you are responsible for
computing dates after the minimum lead time. The product ID should have
been supplied to you by the provider.

Providers may require additional information to be sent; see the 
individual modules for details.

Returns a hash containing the following keys:

    order-id (Required)
    service-id (Required)
    payment-code

=cut

$sigs{order} = [qw/ forename surname building city county postcode telephone
cli client-ref prod-id crd username password care-level /];

=head2 cease

Parameters:

    crd (Required)
    service-id (Required)
    client-ref (Required for Murphx)
    accepts-charges (Optional)
    reason (Optional)

Output is a scalar representing the ID of the cease order for tracking
purposes.

=cut

$sigs{cease} = [ qw/ service-id crd /];

=head2 requestmac

Parameters:

    service-id (Required)
    reason (Required for Murphx)

Returns a hash comprising: mac, expiry-date if the MAC is currently available;
the key "requested" if not.

=cut

$sigs{requestmac} = [ "service-id" ];

1; # End of Net::DSLProvider

=head1 AUTHOR

Simon Cozens, C<< <simon at simon-cozens.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-dslprovider at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-DSLProvider>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::DSLProvider


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-DSLProvider>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-DSLProvider>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-DSLProvider>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-DSLProvider/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to the UK Free Software Network (http://www.ukfsn.org/) for their
support of this module's development. For free-software-friendly hosting
and other Internet services, try UKFSN.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Simon Cozens.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
