class AddPcpSalt < ActiveRecord::Migration[5.1]
  def change
    add_column :people, :pcp_salt, :string
  end
end