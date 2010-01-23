package Net::DSLProvider;
use warnings;
use strict;
use base 'Class::Accessor';
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
Net::DSLProvider::* modules instead.

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

=head2 line_check

    $dsl->line_check( cli => '02072221111', cwllu => 1 );

Returns a hash detailing whether it is possible to provide ADSL on the 
given cli, which classes of service are available and the estimated
maximum speed the line may sustain.

Required parameters: cli
Optional parameters: cwllu bellu

=cut


1; # End of Net::DSLProvider
