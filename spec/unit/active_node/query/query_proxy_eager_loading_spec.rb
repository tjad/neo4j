describe Neo4j::ActiveNode::Query::QueryProxyEagerLoading do
  let(:person_model) { double('Fake Person model') }


  before do
    stub_active_node_class('Person', person_model) do
      property :name
      has_many :out, :brothers, type: :HAS_BROTHER, model_class: :Person
      has_many :out, :sisters, type: :HAS_SISTER, model_class: :Person
      has_many :out, :sons, type: :HAS_SON, model_class: :Person
      has_many :out, :daughters, type: :HAS_DAUGHTER, model_class: :Person
      has_many :out, :children, type: :HAS_CHILDREN, model_class: :Person
      has_one :out, :favourite, type: :HAS_FAVOURITE, model_class: :Person
    end
  end

  describe 'with_associations spec' do
    context '1 model family composition' do
      before(:each) do
        Person.delete_all
        # Create associations
        parent.sisters << aunt
        aunt.children << nephew
        aunt.children << niece
        aunt.sons << nephew
        aunt.daughters << niece
        aunt.favourite = parent
      end

      # Create Person Objects
      let!(:parent) { Person.create(name: 'Jack') }
      let!(:aunt) { Person.create(name: 'Jill') }
      let!(:nephew) { Person.create(name: 'Johnny') }
      let!(:niece) { Person.create(name: 'Janice') }

      it 'fetches full structure with model association depth > 2' do
        expect(Neo4j::ActiveBase).to_not receive(:run_transaction)

        result = Person.where(name: parent.name).with_associations(sisters: [:children]).first

        expect(result).to be_a(Person)

        expect(result.sisters).to be_a(Neo4j::ActiveNode::HasN::AssociationProxy)
        result_aunt = result.sisters.first

        expect(result_aunt).to be_a(Person)
        expect(result_aunt[:name]).to eql(aunt[:name])

        expect(result_aunt.children).to be_a(Neo4j::ActiveNode::HasN::AssociationProxy)
        result_child = result_aunt.children.first

        expect(result_child).to be_a(Person)
        expect(result_child[:name]).to eql(niece.name)
      end
    end
  end
end
