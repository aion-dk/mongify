module Mongify
  class Translation
    #
    # This module does the processing on the translation object
    #
    module Process
      attr_accessor :sql_connection, :no_sql_connection
      # Does the actual act of processing the translation.
      # Takes in boht a sql connection and a no sql connection
      def process(sql_connection, no_sql_connection)
        raise Mongify::SqlConnectionRequired, "Can only read from Mongify::Database::SqlConnection" unless sql_connection.is_a?(Mongify::Database::SqlConnection)
        raise Mongify::NoSqlConnectionRequired, "Can only write to Mongify::Database::NoSqlConnection" unless no_sql_connection.is_a?(Mongify::Database::NoSqlConnection)
        
        self.sql_connection = sql_connection
        raise SqlConnectionInvalid, "SQL Connection is not valid" unless self.sql_connection.valid?
        self.no_sql_connection = no_sql_connection
        raise NoSqlConnectionInvalid, "noSql Connection is not valid" unless self.no_sql_connection.valid?
        
        no_sql_connection.ask_to_drop_database if no_sql_connection.forced?
        
        setup_db_index
        copy_data
        copy_embedded_tables
        update_reference_ids
        remove_pre_mongified_ids
        nil
      end
      
      #######
      private
      #######
      
      # Setups up pre_mongifed_id as an index to speed up lookup performance
      def setup_db_index
        self.copy_tables.each do |t|
          no_sql_connection.create_pre_mongified_id_index(t.name)
        end
      end
      
      # Does the straight copy (of tables)
      def copy_data
        self.copy_tables.each do |t|
          rows = sql_connection.select_rows(t.sql_name)
          Mongify::Status.publish('copy_data', :size => rows.count, :name => "Copying #{t.name}", :action => 'add')
          rows.each do |row|
            no_sql_connection.insert_into(t.name, t.translate(row))
            Mongify::Status.publish('copy_data')
          end
          Mongify::Status.publish('copy_data', :action => 'finish')
        end
      end
      
      # Does a copy of the embedded tables
      def copy_embedded_tables
        self.embed_tables.each do |t|
          rows = sql_connection.select_rows(t.sql_name)
          Mongify::Status.publish('copy_embedded', :size => rows.count, :name => "Embedding #{t.name}", :action => 'add')
          rows.each do |row|
            table_name = if t.embed_in_polymorphic.present?
              type_column = t.embed_in_polymorphic + "_type"
              row[type_column].try :tableize
            else
              t.embed_in
            end

            puts "Embed polymorphic: type_column: #{type_column} table_name: #{table_name}"

            next unless table_name
            target_row = no_sql_connection.find_one(table_name, {:pre_mongified_id => row[t.embed_on]})
            next unless target_row.present?
            # puts "target_row = #{target_row.inspect}", "---"
            row, parent_row = t.translate(row, target_row)
            parent_row ||= {}
            parent_row.delete("_id")
            parent_row.delete(t.name.to_s)
            #puts "parent_row = #{parent_row.inspect}", "---"
            row.delete(t.embed_on)
            row.merge!(fetch_reference_ids(t, row))
            row.delete('pre_mongified_id')
            save_function_call = t.embedded_as_object? ? '$set' : '$addToSet'
            no_sql_connection.update(table_name, target_row['_id'], append_parent_object({save_function_call => {t.name => row}}, parent_row))
            Mongify::Status.publish('copy_embedded')
          end
          Mongify::Status.publish('copy_embedded', :action => 'finish')
        end
      end
            
      # Updates the reference ids in the no sql database
      def update_reference_ids
        self.copy_tables.each do |t|
          rows = no_sql_connection.select_rows(t.name)
          Mongify::Status.publish('update_references', :size => rows.count, :name => "Updating References #{t.name}", :action => 'add')
          rows.each do |row|
            id = row["_id"]
            attributes = fetch_reference_ids(t, row)
            no_sql_connection.update(t.name, id, {"$set" => attributes}) unless attributes.blank?
            Mongify::Status.publish('update_references')
          end
          Mongify::Status.publish('update_references', :action => 'finish')
        end
      end
      
      # Fetches the new _id from a collection
      def fetch_reference_ids(table, row)
        attributes = {}
        table.reference_columns.each do |c|
          new_id = nil
          table_name = if c.polymorphic
            type_column = c.sql_name.gsub(/_id$/, '') + "_type"
            row[type_column].try :tableize
          else
            c.references.to_s
          end

          if table_name
            if row[c.name.to_s].is_a?(Array)
              new_id = []
              row[c.name.to_s].each do |old_id|
                new_id << no_sql_connection.get_id_using_pre_mongified_id(table_name, old_id)
              end
            else
              new_id = no_sql_connection.get_id_using_pre_mongified_id(table_name, row[c.name.to_s])
            end
            attributes.merge!(c.name => new_id) unless new_id.nil?
          end
        end
        attributes
      end
      
      # Removes 'pre_mongiifed_id's from all collection
      def remove_pre_mongified_ids
        self.copy_tables.each do |t| 
          Mongify::Status.publish('remove_pre_mongified', :size => 1, :name => "Removing pre_mongified_id #{t.name}", :action => 'add')
          no_sql_connection.remove_pre_mongified_ids(t.name)
          Mongify::Status.publish('remove_pre_mongified', :action => 'finish')
        end
      end
      
      # Used to append parent object values to an embedded update call
      def append_parent_object(object, parent)
        return object if parent.blank?
        object["$set"] = object.has_key?('$set') ? object["$set"].merge(parent) : parent
        object
      end
      
      
    end
  end
end
