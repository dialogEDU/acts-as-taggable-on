module ActsAsTaggableOn
  module TagsHelper
    # See the wiki for an example using tag_cloud.
    def tag_cloud(tags, classes)
      return [] if tags.empty?

      max_count = tags.sort_by(&:taggings_count).last.taggings_count.to_f

      tags.each do |tag|
        index = ((tag.taggings_count / max_count) * (classes.size - 1))
        yield tag, classes[index.nan? ? 0 : index.round]
      end
    end

    def tag_search
      tag_partial_name = params[:search]+'%'
      @tags = ActsAsTaggableOn::Tag.where(["name LIKE ? and account = ?" , tag_partial_name, @account.id])
      output = []
      @tags.each do |t|
        output << [t.name,t.name,nil,t.name]
      end
      render layout: false, json: output
    end
  end
end
