class CreateCameraFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :camera_feeds do |t|
      t.references :vehicle, null: false, foreign_key: true
      t.string :image_url
      t.text :ai_analysis
      t.string :status

      t.timestamps
    end
  end
end
