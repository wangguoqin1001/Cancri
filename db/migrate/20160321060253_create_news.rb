class CreateNews < ActiveRecord::Migration[5.0]
  def change
    create_table :news do |t|
      t.string :name
      t.integer :news_type
      t.string :cover
      t.text :content
      t.integer :admin_id
      t.integer :event_id

      t.timestamps
    end
    add_index :news, :name, unique: true
    add_index :news, :news_type
    add_index :news, :admin_id
    add_index :news, :event_id
  end
end
