module Neo4j
  module ActiveNode
    module Query
      module QueryProxyEagerLoading
        def each(node = true, rel = nil, &block)
          return super if with_associations_spec.size.zero?

          query_from_association_spec.pluck(identity, "[#{with_associations_return_clause}]").map do |record, eager_data|
            eager_data.each_with_index do |eager_records, index|
              record.association_proxy(with_associations_spec[index]).cache_result(eager_records)
            end

            yield(record)
          end
        end

        def with_associations_spec
          @with_associations_spec ||= []
        end

        def with_associations(assoc_conf)



          object_name = self.name.gsub(/::/, '/').
              gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
              gsub(/([a-z\d])([A-Z])/,'\1_\2').
              tr("-", "_").
              downcase

          # Construct paths to represent the query paths for information to be eagerly loaded
          paths = []
          # For reconstructing objects
          path_directive_class_table = {}


          path_constructor = lambda do |current_path, path_conf|

            if path_conf.instance_of? Hash
              path_conf.each do |k, v|
                path_constructor.call(current_path+[k], v)
              end
            elsif path_conf.instance_of? Array
              path_conf.each do |path|
                paths << current_path + [path]
              end
            elsif path_conf.instance_of? Symbol # Append to current path and add to paths local variable
              current_path << path_conf
              paths << current_path
            else
              raise Exception.new("Unhandled path type")
            end
          end

          path_constructor.call([], assoc_conf)

          # Construct cypher queries
          proxy_set = []

          path_directive_class_table[object_name.to_sym] = self.model

          paths.each do |path|
            proxy = self.model.query_proxy.as(object_name.to_sym)

            path.each do |path_directive|
              proxy = proxy.send(path_directive, path_directive)
              path_directive_class_table[path_directive] = proxy.model
            end

            proxy_set << proxy
          end


          assoc_chain = [object_name.to_sym] + paths.first

          # Perform queries to gather information from database for eager loading
          matches = proxy_set.first.pluck(*assoc_chain)

          # Embed the nodes correctly within the object in order to reconstruct the model
          link_nodes = lambda do |match, parent, path|
            return parent if path.empty?

            path_member = path.shift
            path_obj = match[assoc_chain.find_index(path_member)]

            if parent.nil?
              link_nodes.call(match, path_obj, path)
            else
              value = link_nodes.call(match, path_obj, path)
              parent.write_attribute(path_member,[value], {write_to_cache: true})
              parent
            end
          end


          matches.map do |match|
            link_nodes.call(match, nil, assoc_chain.dup)
          end
        end

        private

        def with_associations_return_clause(variables = with_associations_spec)
          variables.map { |n| "#{n}_collection" }.join(',')
        end

        def query_from_association_spec
          previous_with_variables = []
          with_associations_spec.inject(query_as(identity).with(identity)) do |query, association_name|
            with_association_query_part(query, association_name, previous_with_variables).tap do
              previous_with_variables << association_name
            end
          end.return(identity)
        end

        def with_association_query_part(base_query, association_name, previous_with_variables)
          association = model.associations[association_name]

          base_query.optional_match("(#{identity})#{association.arrow_cypher}(#{association_name})")
                    .where(association.target_where_clause)
                    .with(identity, "collect(#{association_name}) AS #{association_name}_collection", *with_associations_return_clause(previous_with_variables))
        end
      end
    end
  end
end
