package Net::DSLProvider::Cerberus;
use base 'Net::DSLProvider';
use Net::DSLProvider::Cerberus::soap;
__PACKAGE__->mk_accessors(qw/clientid/);

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


1;
