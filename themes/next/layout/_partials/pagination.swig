{% if page.prev or page.next %}
  <nav class="pagination">
    {{
      paginator({
        prev_text: '<Prev',
        next_text: 'Next>',
        mid_size: 1
      })
    }}
  </nav>
{% endif %}
