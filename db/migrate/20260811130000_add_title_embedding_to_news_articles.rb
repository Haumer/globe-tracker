class AddTitleEmbeddingToNewsArticles < ActiveRecord::Migration[7.1]
  def change
    # Not pgvector. The gate never searches -- candidate_clusters has already
    # narrowed to at most 150 clusters by the time a cosine is wanted, so this
    # is an in-memory dot product over a few hundred vectors. The extension
    # earns its place at candidate generation, which is a separate change.
    #
    # double precision[] rather than real[], which would halve the 63MB this
    # costs at full corpus: the schema dumper has no representation for real[]
    # and renders it as `t.float`, so db:schema:load would build a column of a
    # different type than the migration did. A silent divergence between the
    # test schema and this one is not worth 30MB.
    add_column :news_articles, :title_embedding, :float, array: true
    add_column :news_articles, :title_embedding_model, :string
    # Digest of the exact text that was embedded, so a re-run re-embeds only
    # the rows whose headline changed and a model or dimension switch
    # invalidates the corpus rather than silently mixing two vector spaces.
    add_column :news_articles, :title_embedding_digest, :string

    add_index :news_articles, :id,
      where: "title_embedding IS NULL AND title IS NOT NULL",
      name: "index_news_articles_pending_title_embedding"
  end
end
