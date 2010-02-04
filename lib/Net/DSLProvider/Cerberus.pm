package Net::DSLProvider::Cerberus;
use base 'Net::DSLProvider';
use Net::DSLProvider::Cerberus::soap;

sub _credentials {
    my $self = shift;
    return SOAP::Header->new(
      name =>'AuthenticatedUser',
      attr => { xmlns => "http://nc.cerberusnetworks.co.uk/NetCONNECT" },
      value => {username => $self->{user}, password => $self->{pass} },
    );
}


1;
